package Bibliotech::User;
use strict;
use base 'Bibliotech::DBI';
use List::Util qw/min max/;
use Bibliotech::Query;
use Digest::MD5 qw/md5_hex/;

__PACKAGE__->table('user');
__PACKAGE__->columns(Primary => qw/user_id/);
__PACKAGE__->columns(Essential => qw/username openurl_resolver openurl_name updated/);
__PACKAGE__->columns(Others => qw/password active firstname lastname email verifycode author captcha_karma library_comment reminder_email last_deletion quarantined origin created/);
__PACKAGE__->columns(TEMP => qw/gangs_packed user_articles_count_packed/);
__PACKAGE__->force_utf8_columns(qw/username firstname lastname/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->datetime_column('updated', 'before_update');
__PACKAGE__->datetime_column('last_deletion');
__PACKAGE__->datetime_column('reminder_email');
__PACKAGE__->has_many(user_articles_raw => 'Bibliotech::User_Article');
__PACKAGE__->has_many(articles => ['Bibliotech::User_Article' => 'article']);
__PACKAGE__->has_many(user_gangs => 'Bibliotech::User_Gang');
__PACKAGE__->has_many(gangs_without_ownership => ['Bibliotech::User_Gang' => 'gang']);
__PACKAGE__->has_a(author => 'Bibliotech::Author');
__PACKAGE__->has_a(library_comment => 'Bibliotech::Comment');
__PACKAGE__->has_many(openids => 'Bibliotech::User_Openid');

sub by_openid_actual {
  my $url_str = pop;
  my $url = UNIVERSAL::isa($url_str, 'URI') ? $url_str : URI->new($url_str);
  my $openid_check = Bibliotech::User_Openid->search(openid => $url);
  my $link = $openid_check->first or return;
  return Bibliotech::User->retrieve($link->user);
}

sub by_openid {
  my ($class, $url) = @_;
  return $class->by_openid_actual(_with_trailing_slash($url)) ||
         $class->by_openid_actual(_without_trailing_slash($url));
}

sub _with_trailing_slash {
  local $_ = pop;
  return $_ if m|/$|;
  return $_.'/';
}

sub _without_trailing_slash {
  local $_ = pop;
  return $_ unless m|/$|;
  return substr($_, 0, -1);
}

sub create_for_openid {
  my ($class, $openid, $username, $firstname, $lastname, $email) = @_;
  if ($email) {
    my ($existing) = Bibliotech::User->search(email => $email);
    die "The email address $email is already registered in our user database and may be associated with another OpenID.\n" if defined $existing;
  }
  my $dbh = Bibliotech::DBI::db_Main;
  $dbh->do('SET AUTOCOMMIT=0');
  my $user = eval {
    my $user = Bibliotech::User->create({username => 'oi_'.md5_hex($openid),
					 password => substr(md5_hex('password:'.$openid), 0, 10),
					 origin   => 'openid',
					});
    if ($username) {
      eval { _validate_username($username); };
      unless ($@) {
	$user->username($username);
	eval { $user->update; };
	$username = undef if $@;
      };
    }
    unless ($username) {
      $user->username('openid'.$user->user_id);
      $user->update;
    }
    if ($email) {
      eval { _validate_email($email); };
      unless ($@) {
	$user->email($email);
	eval { $user->update; };
	$email = undef if $@;
      }
    }
    if ($firstname or $lastname) {
      if ($firstname) {
	eval { _validate_firstname($firstname); };
	$user->firstname($firstname) unless $@;
      }
      if ($lastname) {
	eval { _validate_lastname($lastname); };
	$user->lastname($lastname) unless $@;
      }
      $user->update;
    }
    $user->add_to_openids({openid => $openid});
    return $user;
  };
  if (my $e = $@) {
    $dbh->do('ROLLBACK');
    $dbh->do('SET AUTOCOMMIT=1');
    die $e;
  }
  $dbh->do('COMMIT');
  $dbh->do('SET AUTOCOMMIT=1');
  return $user;
}

# simulate the behavior of a field with an external table
sub openid {
  my $self = shift;
  if (@_) {
    Bibliotech::User_Openid->search(user => $self)->delete_all;
    my $openid_str_or_obj = shift;
    defined $openid_str_or_obj or return;
    my $openid = "$openid_str_or_obj" or return;
    $self->add_to_openids({openid => $openid});
    return $openid;
  }
  my ($openid) = Bibliotech::User_Openid->search(user => $self);
  return $openid;
}

sub is_unnamed_openid {
  my $self = shift;
  return $self->origin eq 'openid' && $self->username =~ /^(?:oi_[a-z0-9]{32}|openid_?\d+)$/;
}

sub captcha_karma_not_undef {
  my $karma = shift->captcha_karma;
  return 0 unless defined $karma;
  return $karma;
}

sub mark_captcha_shown_first {
  my $self = shift;
  $self->captcha_karma(max($self->captcha_karma_not_undef - 1, -10));
  $self->update;
}

sub mark_captcha_shown_repeat {
  # noop
}

sub mark_captcha_passed {
  my $self = shift;
  $self->captcha_karma(min($self->captcha_karma_not_undef + 1.2, 10));
  $self->update;
}

sub mark_captcha_failed {
  # noop
}

sub is_captcha_karma_bad {
  shift->captcha_karma_not_undef <= -2;
}

sub my_alias {
  'u';
}

sub retrieve {
  my ($self, $user_id) = @_;
  my $quick = $Bibliotech::Apache::QUICK{'Bibliotech::User::retrieve'}->{$user_id};
  return $quick if defined $quick;
  #warn "non-quick User retrieve $user_id from ".join(', ',caller(0));
  my $user = $self->SUPER::retrieve($user_id);
  $Bibliotech::Apache::QUICK{'Bibliotech::User::retrieve'}->{$user_id} = $user;
  return $user;
}

sub update {
  my $self = shift;
  $Bibliotech::Apache::QUICK{'Bibliotech::User::retrieve'}->{$self->user_id} = undef;
  return $self->SUPER::update(@_);
}

# run through Bibliotech::Query to get privacy control, and later, maybe caching
sub user_articles {
  my $self = shift;
  my $q = new Bibliotech::Query;
  $q->set_user($self);
  $q->activeuser($Bibliotech::Apache::USER);
  return $q->user_articles;
}

# call count_user_articles() and the privacy parameter is handled for you
__PACKAGE__->set_sql(count_user_articles_need_privacy => <<'');
SELECT 	 COUNT(*)
FROM     __TABLE(Bibliotech::User_Article=ua)__
WHERE    ua.user = ? AND %s

sub count_user_articles {
  my $self = shift;
  my $packed = $self->user_articles_count_packed;
  return $packed if defined $packed;
  my ($privacywhere, @privacybind) = Bibliotech::Query->privacywhere($Bibliotech::Apache::USER);
  my $sth = $self->sql_count_user_articles_need_privacy($privacywhere);
  $sth->execute($self, @privacybind);
  my ($count) = $sth->fetchrow_array;
  $sth->finish;
  return $count;
}

__PACKAGE__->set_sql(count_user_articles => <<'');
SELECT 	 COUNT(*)
FROM     __TABLE(Bibliotech::User_Article=ua)__
WHERE    ua.user = ?

sub is_library_empty {
  my $self = shift;
  my $sth = $self->sql_count_user_articles;
  $sth->execute($self);
  my ($count) = $sth->fetchrow_array;
  $sth->finish;
  return $count == 0;
}

__PACKAGE__->set_sql(count_tags_no_privacy => <<'');
SELECT 	 COUNT(DISTINCT t.tag_id)
FROM     __TABLE(Bibliotech::User_Article=ua)__,
         __TABLE(Bibliotech::User_Article_Tag=uat)__,
         __TABLE(Bibliotech::Tag=t)__
WHERE    ua.user = ?
AND      __JOIN(ua uat)__
AND      __JOIN(uat t)__

sub count_tags_no_privacy {
  my $self = shift;
  my $sth = $self->sql_count_tags_no_privacy;
  $sth->execute($self);
  my ($count) = $sth->fetchrow_array;
  $sth->finish;
  return $count;
}

__PACKAGE__->set_sql(count_recent_posts_no_privacy => <<'');
SELECT   COUNT(*)
FROM     __TABLE(Bibliotech::User_Article=ua)__
WHERE    ua.user = ?
AND      ua.created > NOW() - INTERVAL %s

sub count_recent_posts_no_privacy {
  my ($self, $window_spec) = @_;
  my $window = $self->untaint_time_window_spec($window_spec);
  my $sth = $self->sql_count_recent_posts_no_privacy($window);
  $sth->execute($self);
  my ($count) = $sth->fetchrow_array;
  $sth->finish;
  return $count;
}

__PACKAGE__->set_sql(count_host_posts_no_privacy => <<'');
SELECT   COUNT(ua.user_article_id)
FROM     __TABLE(Bibliotech::User_Article=ua)__,
         __TABLE(Bibliotech::Article=a)__,
         __TABLE(Bibliotech::Bookmark=b)__
WHERE    ua.user = ?
AND      b.url LIKE CONCAT('http://', ?, '%%')
AND      __JOIN(ua a)__
AND      __JOIN(a b)__

sub count_host_posts_no_privacy {
  my ($self, $host) = @_;
  my $sth = $self->sql_count_host_posts_no_privacy;
  $sth->execute($self, $host);
  my ($count) = $sth->fetchrow_array;
  $sth->finish;
  return $count;
}

# list gangs, but keep private gangs private
sub gangs_raw {
  my $self = shift;
  my $user_id = $self->user_id;
  my $quick = $Bibliotech::Apache::QUICK{'Bibliotech::User::gangs'}->{$user_id};
  return @{$quick} if defined $quick;
  my $active_user_id = $Bibliotech::Apache::USER_ID;
  my $sth = Bibliotech::Gang->sql_from_user_packed;
  $sth->execute($active_user_id, $user_id, $active_user_id);
  my @gangs = map(Bibliotech::Gang->construct($_), $sth->fetchall_hash);
  $Bibliotech::Apache::QUICK{'Bibliotech::User::gangs'}->{$user_id} = \@gangs;
  return @gangs;
}

sub gangs {
  shift->packed_or_raw('Bibliotech::Gang', 'gangs_packed', 'gangs_raw');
}

# run through Bibliotech::Query to get privacy control, and later, maybe caching
sub tags {
  my $self = shift;
  my $q = new Bibliotech::Query;
  $q->set_user($self);
  $q->activeuser($Bibliotech::Apache::USER);
  return $q->tags(@_);
}

sub tags_alpha {
  my $self = shift;
  my %options = @_;
  $options{sort} = 't.name';
  $options{sortdir} = 'ASC';
  return $self->tags(%options);
}

__PACKAGE__->set_sql(my_tags_alpha_need_packed => <<'');
SELECT 	 %s
FROM     __TABLE(Bibliotech::User_Article=ua)__,
         __TABLE(Bibliotech::User_Article_Tag=uat)__,
         __TABLE(Bibliotech::Tag=t)__
WHERE    ua.user = ?
AND      __JOIN(ua uat)__
AND      __JOIN(uat t)__
GROUP BY t.tag_id
ORDER BY t.name

sub my_tags_alpha {
  my $self = shift;
  my $sth = Bibliotech::User->sql_my_tags_alpha_need_packed(join(', ', Bibliotech::Tag->packed_select));
  $sth->execute($self->user_id);
  return map(Bibliotech::Tag->construct($_), $sth->fetchall_hash);
}

sub unique {
  'username';
}

sub username_possessive {
  shift->username."\'s";
}

sub visit_link {
  my ($self, $bibliotech, $class) = @_;
  return $bibliotech->cgi->div({class => ($class || 'referent')},
			       'Visit',
			       $self->link($bibliotech, undef, 'href_search_global', 'username_possessive', 1),
			       $bibliotech->sitename,
			       'library.'
			       );
}

sub name {
  shift->collective_name(@_);
}

__PACKAGE__->set_sql(from_tag => <<'');
SELECT 	 __ESSENTIAL(c4)__
FROM     __TABLE(Bibliotech::Tag=c1)__,
       	 __TABLE(Bibliotech::User_Article_Tag=c2)__,
       	 __TABLE(Bibliotech::User_Article=c3)__,
   	 __TABLE(Bibliotech::User=c4)__
WHERE  	 __JOIN(c1 c2)__
AND    	 __JOIN(c2 c3)__
AND    	 __JOIN(c3 c4)__
AND    	 c1.tag_id = ?
GROUP BY c4.user_id
ORDER BY c4.username

sub link_bookmark {
  # auto 'add_to_bookmarks' is insufficient, see http://www.class-dbi.com/cgi-bin/wiki/index.cgi?ComplexManyToMany
  my $self = shift;
  my $create = 1;
  $create = shift if @_ && !ref($_[0]) && $_[0] eq '0';
  my @ua;
  foreach (@_) {
    my $b = $_;
    my $a;
    ($b, $a) = @{$b} if ref $b eq 'ARRAY';
    my $bookmark = Bibliotech::Bookmark->new($b, $create);
    next unless $bookmark;
    my $method = $create ? 'find_or_create' : 'search';
    my $article = $a || do { local $_ = $bookmark->article; defined $_ && $_->id != 0 ? $_ : undef }
                     || (Bibliotech::Article->$method({hash => $bookmark->hash}))[0];
    next unless $article;
    $bookmark->article($article) if not defined $bookmark->article or $bookmark->article->id == 0;
    my $user_article;
    my ($generic_user_article) = Bibliotech::User_Article->search({user => $self, article => $article});
    if ($generic_user_article) {
      $user_article = $generic_user_article;
      if ($user_article->bookmark->id != $bookmark->id) {
	$user_article->bookmark($bookmark);
	$user_article->mark_updated;
      }
    }
    else {
      ($user_article) = Bibliotech::User_Article->$method({user => $self, article => $article, bookmark => $bookmark});
    }
    next unless $user_article;
    push @ua, $user_article;
    $self->mark_updated;
    $bookmark->mark_updated;
  }
  return wantarray ? @ua : $ua[0];
}

sub find_bookmark {
  shift->link_bookmark(0, @_);
}

sub unlink_bookmark {
  my $self = shift;
  foreach (@_) {
    my $bookmark = ref $_ eq 'Bibliotech::Bookmark' ? $_ : Bibliotech::Bookmark->retrieve($_) or next;
    my ($link) = Bibliotech::User_Bookmark->search(user => $self, bookmark => $bookmark) or next;
    $link->delete;
  }
}

sub link_gang {
  my $self = shift;
  my @ug = map(Bibliotech::User_Gang->find_or_create({user => $self, gang => Bibliotech::Gang->new($_, 1)}), @_);
  return wantarray ? @ug : $ug[0];
}

sub unlink_gang {
  my $self = shift;
  foreach (@_) {
    my $gang = ref $_ eq 'Bibliotech::Gang' ? $_ : Bibliotech::Gang->retrieve($_) or next;
    my ($link) = Bibliotech::User_Gang->search(user => $self, gang => $gang) or next;
    $link->delete;
  }
}

sub last_deletion_now {
  shift->set_datetime_now('last_deletion');
}

__PACKAGE__->set_sql(count_use_of_tag => <<'');
SELECT 	 COUNT(*)
FROM   	 __TABLE(Bibliotech::User_Article=ua)__,
       	 __TABLE(Bibliotech::User_Article_Tag=uat)__
WHERE  	 __JOIN(ua uat)__
AND    	 ua.user = ?
AND      uat.tag = ?

sub count_use_of_tag {
  my ($self, $tag) = @_;
  die 'no tag' unless defined $tag;
  my $sth = $self->sql_count_use_of_tag;
  $sth->execute($self->user_id, $tag->tag_id);
  my $count;
  ($count) = $sth->fetchrow_array;
  $sth->finish;
  return $count;
}

sub standard_annotation_text {
  my ($self, $bibliotech, $register) = @_;
  my $sitename = $bibliotech->sitename;
  my $username = $self->username;
  return "This is a list of the articles and links in the collection of $sitename user $username.
          To create your own $sitename collection, $register";
}

sub openurl_cache_key {
  my $self = shift;
  my $resolver = $self->openurl_resolver or return undef;
  my $name = $self->openurl_name || '';
  return "$resolver/$name";
}

sub count_active {
  # use user_article table; it's faster
  Bibliotech::User_Article->sql_single('COUNT(DISTINCT user)')->select_val;
}

# call search_most_active() and the privacy parameter is handled for you
__PACKAGE__->set_sql(most_active_need_privacy => <<'');
SELECT   DISTINCT __ESSENTIAL(u)__
FROM
(
SELECT   user, COUNT(article) as cnt
FROM     __TABLE(Bibliotech::User_Article)__
GROUP BY user
ORDER BY cnt DESC
LIMIT    50
) as uai
         LEFT JOIN __TABLE(Bibliotech::User=u)__ ON (uai.user = u.user_id)
	 LEFT JOIN __TABLE(Bibliotech::User_Article=ua)__ ON (__JOIN(u ua)__)
WHERE    ua.user_article_id IS NOT NULL AND %s
LIMIT    25;

sub search_most_active {
  my ($self, $visitor) = @_;
  my $user = $visitor ? undef : $Bibliotech::Apache::USER;
  my ($privacywhere, @privacybind) = Bibliotech::Query->privacywhere($user);
  my $sth = $self->sql_most_active_need_privacy($privacywhere);
  return $self->sth_to_objects($sth, \@privacybind);
}

# call search_most_active_in_window() and the privacy parameter is handled for you
__PACKAGE__->set_sql(most_active_in_window_need_privacy => <<'');
SELECT   __ESSENTIAL(u)__,
         COUNT(ua.user_article_id) as sortvalue
FROM
(
SELECT   user_article_id
FROM     __TABLE(Bibliotech::User_Article)__
WHERE    created >= NOW() - INTERVAL %s
UNION
SELECT   user_article_id
FROM     __TABLE(Bibliotech::User_Article)__
WHERE    updated >= NOW() - INTERVAL %s
) AS uai
	 LEFT JOIN __TABLE(Bibliotech::User_Article=ua)__ ON (uai.user_article_id=ua.user_article_id AND %s)
         LEFT JOIN __TABLE(Bibliotech::User=u)__ ON (__JOIN(ua u)__)
WHERE    ua.user_article_id IS NOT NULL
GROUP BY u.user_id
HAVING   sortvalue > 1
ORDER BY sortvalue DESC
LIMIT    25;

sub search_most_active_in_window {
  my ($self, $window_spec, $visitor) = @_;
  my $window = $self->untaint_time_window_spec($window_spec);
  my $user   = $visitor ? undef : $Bibliotech::Apache::USER;
  my ($privacywhere, @privacybind) = Bibliotech::Query->privacywhere($user);
  my $sth = $self->sql_most_active_in_window_need_privacy($window, $window, $privacywhere);
  return $self->sth_to_objects($sth, \@privacybind);
}

# select count(user_id) from user
# where verifycode is null
# and created BETWEEN NOW()-INTERVAL 365 DAY AND NOW()-INTERVAL 15 DAY
# and (select count(user) from user_article where user.user_id = user_article.user) = 0
#
__PACKAGE__->set_sql(no_articles_posted => <<'');
SELECT 	 __ESSENTIAL(u)__
FROM     __TABLE(Bibliotech::User=u)__
WHERE  	 u.verifycode IS NULL
AND      u.reminder_email IS NULL
AND    	 u.created BETWEEN NOW()-INTERVAL 365 DAY AND NOW()-INTERVAL 15 DAY
AND      (SELECT   COUNT(ua.user)
          FROM      __TABLE(Bibliotech::User_Article=ua)__
          WHERE    u.user_id = ua.user) = 0
ORDER BY u.created
LIMIT 100

__PACKAGE__->set_sql(test_no_articles_posted => <<'');
SELECT 	 __ESSENTIAL(u)__
FROM     __TABLE(Bibliotech::User=u)__
WHERE    u.username = 'martin'

# no privacy because it's admin
my $user_table_columns = join(', ', map { 'u.'.$_ } Bibliotech::User->columns);
__PACKAGE__->set_sql(by_admin => <<"");
SELECT 	 $user_table_columns, COUNT(DISTINCT ua.user_article_id) as user_articles_count_packed
FROM     __TABLE(Bibliotech::User=u)__
         LEFT JOIN __TABLE(Bibliotech::User_Article=ua)__ ON (__JOIN(u ua)__)
         LEFT JOIN __TABLE(Bibliotech::User_Gang=ug)__ ON (__JOIN(u ug)__)
         LEFT JOIN __TABLE(Bibliotech::Gang=g)__ ON (__JOIN(ug g)__)
%s
GROUP BY u.user_id
%s
ORDER BY u.user_id

# delete user but first unlink any first_user references
sub delete {
  my $self = shift;

  my $iter = Bibliotech::Bookmark->search(first_user => $self);
  while (my $bookmark = $iter->next) {
    $bookmark->first_user(undef);
    $bookmark->mark_updated;
  }

  $self->SUPER::delete(@_);
}

sub map_all_user_articles {
  my ($self, $action) = @_;

  $Bibliotech::Apache::USER = $self;
  $Bibliotech::Apache::USER_ID = $self->user_id;

  my @errors;
  my $iter = $self->user_articles;
  while (my $user_article = $iter->next) {
    my $id = $user_article->id;
    eval {
      $action->($user_article);
    };
    push @errors, "map_all_user_articles failure on $id: $@" if $@;
  }
  die join("\n", @errors) if @errors;
}

sub delete_all_user_articles {
  my $user = shift;
  eval {
    $user->map_all_user_articles(sub { shift->delete });
    $user->count_user_articles == 0 or die 'count_user_articles not zero! (check database errors)';
  };
  die "problem in delete_all_user_articles for user $user: $@" if $@;
}

sub private_all_user_articles {
  my $user = shift;
  eval {
    $user->map_all_user_articles(sub {
      my $user_article = shift;
      $user_article->private(1);
      $user_article->private_gang(undef);
      $user_article->private_until(undef);
      $user_article->mark_updated;
    });
  };
  die "problem in private_all_user_articles for user $user: $@" if $@;
}

__PACKAGE__->set_sql(quarantine_all_user_articles => <<'');
UPDATE __TABLE(Bibliotech::User_Article)__
SET    quarantined = NOW(),
       def_public = 0,
       updated = NOW()
WHERE  user = ?

sub quarantine_all_user_articles {
  my $user = shift;
  my $sth = $user->sql_quarantine_all_user_articles;
  $sth->execute($user);
  $sth->finish;
}

__PACKAGE__->set_sql(unquarantine_all_user_articles => <<'');
UPDATE __TABLE(Bibliotech::User_Article)__
SET    quarantined = NULL,
       def_public = IF(private = 0 AND private_gang IS NULL AND private_until IS NULL, 1, 0),
       updated = NOW()
WHERE  user = ?

sub unquarantine_all_user_articles {
  my $user = shift;
  my $sth = $user->sql_unquarantine_all_user_articles;
  $sth->execute($user);
  $sth->finish;
}

sub delete_wiki_node {
  my ($self, $bibliotech, $all_nodes) = @_;
  eval "use Bibliotech::Component::Wiki;";
  my $component = Bibliotech::Component::Wiki->new({bibliotech => $bibliotech});
  my $wiki = $component->wiki_obj;
  my $username = $self->username;
  foreach my $nodename ($all_nodes ? (map { "$_" } grep { !$_->is_system } $component->list_only_edited_by_username($wiki, $username))
                                   : ('User:'.$username)) {
    $wiki->delete_node($nodename) if $wiki->node_exists($nodename);
  }
}

sub deactivate_handle_user_articles {
  my ($self, $reason_code) = @_;
  $self->delete_all_user_articles       if $reason_code eq 'resignation';
  $self->quarantine_all_user_articles   if $reason_code eq 'spammer';
  $self->unquarantine_all_user_articles if $reason_code eq 'undo-spammer' or
                                           $reason_code eq 'no-quarantine';
}

sub deactivate_notify_user {
  my ($self, $reason_code, $bibliotech) = @_;
  return unless $reason_code eq 'spammer';
  eval { $bibliotech->notify_user($self, file => 'quarantine_email'); };
  warn $@ if $@;
}

sub deactivate_delete_wiki_node {
  my ($self, $reason_code, $bibliotech) = @_;
  return unless $reason_code eq 'resignation' or $reason_code eq 'spammer' or $reason_code eq 'empty-wiki';
  eval { $self->delete_wiki_node($bibliotech, 1); };
  warn $@ if $@;
}

sub deactivate_update_record {
  my ($self, $reason_code) = @_;
  $self->active(0)                       if $reason_code eq 'resignation';
  $self->set_datetime_now('quarantined') if $reason_code eq 'spammer';
  $self->quarantined(undef)              if $reason_code eq 'undo-spammer';
  $self->mark_updated;
}

sub deactivate_verify_germane {
  my ($self, $reason_code) = @_;
  eval {
    if (!$self->active) {
      die "cannot resign an inactive user\n"       if $reason_code eq 'resignation';
      die "cannot mark inactive user as spammer\n" if $reason_code eq 'spammer';
      die "cannot undo spammer on inactive user\n" if $reason_code eq 'undo-spammer';
      die "cannot unquarantine an inactive user\n" if $reason_code eq 'no-quarantine';
      die "cannot unwiki an inactive user\n"       if $reason_code eq 'empty-wiki';
    }
  };
  die $self->username.': '.$@ if $@;
}

sub deactivate {
  my ($self, $bibliotech, $reason_code) = @_;
  die 'invalid reason code' unless grep { $reason_code eq $_ }
                                        qw/resignation spammer undo-spammer no-quarantine empty-wiki/;
  my $dbh = Bibliotech::DBI->db_Main;
  $dbh->do('SET AUTOCOMMIT=0');
  eval {
    $self->deactivate_verify_germane      ($reason_code);
    $self->deactivate_handle_user_articles($reason_code);
    $self->deactivate_delete_wiki_node    ($reason_code, $bibliotech);
    $self->deactivate_notify_user         ($reason_code, $bibliotech);
    $self->deactivate_update_record       ($reason_code);
  };
  if ($@) {
    $dbh->do('ROLLBACK');
    $dbh->do('SET AUTOCOMMIT=1');
    die $@;
  }
  $dbh->do('COMMIT');
  $dbh->do('SET AUTOCOMMIT=1');
}

sub rename {
  my ($self, $new_username) = @_;
  # make sure we won't clobber someone:
  Bibliotech::User->new($new_username) and die "A user named \"$new_username\" already exists.\n";
  # make sure the new name is legal:
  eval { _validate_username($new_username); };
  die "Cannot accept new username \"$new_username\": $@" if $@;
  # perform the rename:
  $self->username($new_username);
  $self->mark_updated;
}

sub _validate_username {
  my $username = shift;
  $username                or die "You must select a username.\n";
  length $username >= 3    or die "Your username must be at least 3 characters long.\n";
  length $username <= 40   or die "Your username must be no more than 40 characters long.\n";
  $username =~ /^[A-Za-z0-9]+$/ or die "Your username must be composed of alphanumeric characters only (a-z,0-9).\n";
  $username !~ /^\d/       or die "Your username may not start with a digit.\n";
}

sub _validate_password {
  my $password = shift;
  $password                or die "You must select a password.\n";
  length $password >= 4    or die "Your password must be at least 4 characters long.\n";
  length $password <= 40   or die "Your password must be no more than 40 characters long.\n";
}

sub _validate_firstname {
  my $firstname = shift;
  $firstname               or die "You must provide your first name.\n";
  length $firstname <= 40  or die "Your first name must be no more than 40 characters long.\n";
}

sub _validate_lastname {
  my $lastname = shift;
  $lastname                or die "You must provide your last name.\n";
  length $lastname <= 40   or die "Your last name must be no more than 40 characters long.\n";
}

sub _validate_email {
  my $email = shift;
  $email                   or die "You must provide a working email address.\n";
  length $email <= 50      or die "Your email address must be no more than 50 characters long.\n";
  $email =~ /^.+\@.+$/     or die "Invalid email address format.\n";
}

1;
__END__
