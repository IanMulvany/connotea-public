package Bibliotech::User;
use strict;
use base 'Bibliotech::DBI';
use List::Util qw/min max/;
use Bibliotech::Query;

__PACKAGE__->table('user');
#__PACKAGE__->columns(All => qw/user_id username password active firstname lastname email verifycode author last_deletion created updated/);
__PACKAGE__->columns(Primary => qw/user_id/);
__PACKAGE__->columns(Essential => qw/username openurl_resolver openurl_name updated/);
__PACKAGE__->columns(Others => qw/password active firstname lastname email verifycode author captcha_karma library_comment reminder_email last_deletion quarantined created/);
__PACKAGE__->columns(TEMP => qw/gangs_packed user_bookmarks_count_packed/);
__PACKAGE__->force_utf8_columns(qw/username firstname lastname/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->datetime_column('updated', 'before_update');
__PACKAGE__->datetime_column('last_deletion');
__PACKAGE__->datetime_column('reminder_email');
__PACKAGE__->has_many(user_bookmarks_raw => 'Bibliotech::User_Bookmark');
__PACKAGE__->has_many(bookmarks => ['Bibliotech::User_Bookmark' => 'bookmark']);
__PACKAGE__->has_many(user_gangs => 'Bibliotech::User_Gang');
__PACKAGE__->has_many(gangs_without_ownership => ['Bibliotech::User_Gang' => 'gang']);
__PACKAGE__->has_a(author => 'Bibliotech::Author');
__PACKAGE__->has_a(library_comment => 'Bibliotech::Comment');

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
sub user_bookmarks {
  my $self = shift;
  my $q = new Bibliotech::Query;
  $q->set_user($self);
  $q->activeuser($Bibliotech::Apache::USER);
  return $q->user_bookmarks;
}

# call count_user_bookmarks() and the privacy parameter is handled for you
__PACKAGE__->set_sql(count_user_bookmarks_need_privacy => <<'');
SELECT 	 COUNT(*)
FROM     __TABLE(Bibliotech::User_Bookmark=ub)__
WHERE    ub.user = ? AND %s

sub count_user_bookmarks {
  my $self = shift;
  my $packed = $self->user_bookmarks_count_packed;
  return $packed if defined $packed;
  my ($privacywhere, @privacybind) = Bibliotech::Query->privacywhere($Bibliotech::Apache::USER);
  my $sth = $self->sql_count_user_bookmarks_need_privacy($privacywhere);
  $sth->execute($self, @privacybind);
  my ($count) = $sth->fetchrow_array;
  $sth->finish;
  return $count;
}

__PACKAGE__->set_sql(count_user_bookmarks => <<'');
SELECT 	 COUNT(*)
FROM     __TABLE(Bibliotech::User_Bookmark=ub)__
WHERE    ub.user = ?

sub is_library_empty {
  my $self = shift;
  my $sth = $self->sql_count_user_bookmarks;
  $sth->execute($self);
  my ($count) = $sth->fetchrow_array;
  $sth->finish;
  return $count == 0;
}

__PACKAGE__->set_sql(count_tags_no_privacy => <<'');
SELECT 	 COUNT(DISTINCT t.tag_id)
FROM     __TABLE(Bibliotech::User_Bookmark=ub)__,
         __TABLE(Bibliotech::User_Bookmark_Tag=ubt)__,
         __TABLE(Bibliotech::Tag=t)__
WHERE    ub.user = ?
AND      __JOIN(ub ubt)__
AND      __JOIN(ubt t)__

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
FROM     __TABLE(Bibliotech::User_Bookmark=ub)__
WHERE    ub.user = ?
AND      ub.created > NOW() - INTERVAL %s

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
SELECT   COUNT(ub.user_bookmark_id)
FROM     __TABLE(Bibliotech::User_Bookmark=ub)__,
         __TABLE(Bibliotech::Bookmark=b)__
WHERE    ub.user = ?
AND      b.url LIKE CONCAT('http://', ?, '%%')
AND      __JOIN(ub b)__

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
FROM     __TABLE(Bibliotech::User_Bookmark=ub)__,
         __TABLE(Bibliotech::User_Bookmark_Tag=ubt)__,
         __TABLE(Bibliotech::Tag=t)__
WHERE    ub.user = ?
AND      __JOIN(ub ubt)__
AND      __JOIN(ubt t)__
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
       	 __TABLE(Bibliotech::User_Bookmark_Tag=c2)__,
       	 __TABLE(Bibliotech::User_Bookmark=c3)__,
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
  my @ub;
  foreach (@_) {
    my $bookmark = Bibliotech::Bookmark->new($_, $create);
    next unless $bookmark;
    my $method = $create ? 'find_or_create' : 'search';
    my ($user_bookmark) = Bibliotech::User_Bookmark->$method({user => $self, bookmark => $bookmark});
    next unless $user_bookmark;
    push @ub, $user_bookmark;
    $self->mark_updated;
    $bookmark->mark_updated;
  }
  return wantarray ? @ub : $ub[0];
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
FROM   	 __TABLE(Bibliotech::User_Bookmark=ub)__,
       	 __TABLE(Bibliotech::User_Bookmark_Tag=ubt)__
WHERE  	 __JOIN(ub ubt)__
AND    	 ub.user = ?
AND      ubt.tag = ?

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
  # use user_bookmark table; it's faster
  Bibliotech::User_Bookmark->sql_single('COUNT(DISTINCT user)')->select_val;
}

# call search_most_active() and the privacy parameter is handled for you
__PACKAGE__->set_sql(most_active_need_privacy => <<'');
SELECT   DISTINCT __ESSENTIAL(u)__
FROM
(
SELECT   user, COUNT(bookmark) as cnt
FROM     __TABLE(Bibliotech::User_Bookmark)__
GROUP BY user
ORDER BY cnt DESC
LIMIT    50
) as ubi
         LEFT JOIN __TABLE(Bibliotech::User=u)__ ON (ubi.user = u.user_id)
	 LEFT JOIN __TABLE(Bibliotech::User_Bookmark=ub)__ ON (__JOIN(u ub)__)
WHERE    ub.user_bookmark_id IS NOT NULL AND %s
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
         COUNT(ub.user_bookmark_id) as sortvalue
FROM
(
SELECT   user_bookmark_id
FROM     __TABLE(Bibliotech::User_Bookmark)__
WHERE    created >= NOW() - INTERVAL %s
UNION
SELECT   user_bookmark_id
FROM     __TABLE(Bibliotech::User_Bookmark)__
WHERE    updated >= NOW() - INTERVAL %s
) AS ubi
	 LEFT JOIN __TABLE(Bibliotech::User_Bookmark=ub)__ ON (ubi.user_bookmark_id=ub.user_bookmark_id AND %s)
         LEFT JOIN __TABLE(Bibliotech::User=u)__ ON (__JOIN(ub u)__)
WHERE    ub.user_bookmark_id IS NOT NULL
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
# and (select count(user) from user_bookmark where user.user_id = user_bookmark.user) = 0
#
__PACKAGE__->set_sql(no_bookmarks_posted => <<'');
SELECT 	 __ESSENTIAL(u)__
FROM     __TABLE(Bibliotech::User=u)__
WHERE  	 u.verifycode IS NULL
AND      u.reminder_email IS NULL
AND    	 u.created BETWEEN NOW()-INTERVAL 365 DAY AND NOW()-INTERVAL 15 DAY
AND      (SELECT   COUNT(ub.user)
          FROM      __TABLE(Bibliotech::User_Bookmark=ub)__
          WHERE    u.user_id = ub.user) = 0
ORDER BY u.created
LIMIT 100

__PACKAGE__->set_sql(test_no_bookmarks_posted => <<'');
SELECT 	 __ESSENTIAL(u)__
FROM     __TABLE(Bibliotech::User=u)__
WHERE    u.username = 'martin'

# no privacy because it's admin
my $user_table_columns = join(', ', map { 'u.'.$_ } Bibliotech::User->columns);
__PACKAGE__->set_sql(by_admin => <<"");
SELECT 	 $user_table_columns, COUNT(DISTINCT ub.user_bookmark_id) as user_bookmarks_count_packed
FROM     __TABLE(Bibliotech::User=u)__
         LEFT JOIN __TABLE(Bibliotech::User_Bookmark=ub)__ ON (__JOIN(u ub)__)
         LEFT JOIN __TABLE(Bibliotech::User_Gang=ug)__ ON (__JOIN(u ug)__)
         LEFT JOIN __TABLE(Bibliotech::Gang=g)__ ON (__JOIN(ug g)__)
%s
GROUP BY u.user_id
%s
ORDER BY u.user_id

# delete user but first unlink any first_user references
sub delete {
  #warn 'delete user';
  my $self = shift;

  my $iter = Bibliotech::Bookmark->search(first_user => $self);
  while (my $bookmark = $iter->next) {
    $bookmark->first_user(undef);
    $bookmark->mark_updated;
  }

  $self->SUPER::delete(@_);
}

sub map_all_user_bookmarks {
  my ($self, $action) = @_;

  $Bibliotech::Apache::USER = $self;
  $Bibliotech::Apache::USER_ID = $self->user_id;

  my @errors;
  my $iter = $self->user_bookmarks;
  while (my $user_bookmark = $iter->next) {
    my $id = $user_bookmark->id;
    eval {
      $action->($user_bookmark);
    };
    push @errors, "map_all_user_bookmarks failure on $id: $@" if $@;
  }
  die join("\n", @errors) if @errors;
}

sub delete_all_user_bookmarks {
  my $user = shift;
  eval {
    $user->map_all_user_bookmarks(sub { shift->delete });
    $user->count_user_bookmarks == 0 or die 'count_user_bookmarks not zero! (check database errors)';
  };
  die "problem in delete_all_user_bookmarks for user $user: $@" if $@;
}

sub private_all_user_bookmarks {
  my $user = shift;
  eval {
    $user->map_all_user_bookmarks(sub {
      my $user_bookmark = shift;
      $user_bookmark->private(1);
      $user_bookmark->private_gang(undef);
      $user_bookmark->private_until(undef);
      $user_bookmark->mark_updated;
    });
  };
  die "problem in private_all_user_bookmarks for user $user: $@" if $@;
}

__PACKAGE__->set_sql(quarantine_all_user_bookmarks => <<'');
UPDATE __TABLE(Bibliotech::User_Bookmark)__
SET    quarantined = NOW(),
       def_public = 0,
       updated = NOW()
WHERE  user = ?

sub quarantine_all_user_bookmarks {
  my $user = shift;
  my $sth = $user->sql_quarantine_all_user_bookmarks;
  $sth->execute($user);
  $sth->finish;
}

__PACKAGE__->set_sql(unquarantine_all_user_bookmarks => <<'');
UPDATE __TABLE(Bibliotech::User_Bookmark)__
SET    quarantined = NULL,
       def_public = IF(private = 0 AND private_gang IS NULL AND private_until IS NULL, 1, 0),
       updated = NOW()
WHERE  user = ?

sub unquarantine_all_user_bookmarks {
  my $user = shift;
  my $sth = $user->sql_unquarantine_all_user_bookmarks;
  $sth->execute($user);
  $sth->finish;
}

sub delete_wiki_node {
  my ($self, $bibliotech) = @_;
  eval "use Bibliotech::Component::Wiki;";
  my $component = Bibliotech::Component::Wiki->new({bibliotech => $bibliotech});
  my $wiki = $component->wiki_obj;
  my $node = 'User:'.$self->username;
  $wiki->delete_node($node) if $wiki->node_exists($node);
}

sub deactivate_handle_user_bookmarks {
  my ($self, $reason_code) = @_;
  $self->delete_all_user_bookmarks       if $reason_code eq 'resignation';
  $self->quarantine_all_user_bookmarks   if $reason_code eq 'spammer';
  $self->unquarantine_all_user_bookmarks if $reason_code eq 'undo-spammer' or
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
  return unless $reason_code eq 'spammer';
  eval { $self->delete_wiki_node($bibliotech); };
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
    }
  };
  die $self->username.': '.$@ if $@;
}

sub deactivate {
  my ($self, $bibliotech, $reason_code) = @_;
  die 'invalid reason code' unless grep { $reason_code eq $_ }
                                        qw/resignation spammer undo-spammer no-quarantine/;
  my $dbh = Bibliotech::DBI->db_Main;
  $dbh->do('SET AUTOCOMMIT=0');
  eval {
    $self->deactivate_verify_germane($reason_code);
    $self->deactivate_handle_user_bookmarks($reason_code);
    $self->deactivate_delete_wiki_node($reason_code, $bibliotech);
    $self->deactivate_notify_user($reason_code, $bibliotech);
    $self->deactivate_update_record($reason_code);
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
  Bibliotech::User->new($new_username) and die "A user named \"$new_username\" already exists.\n";
  $self->username($new_username);
  $self->mark_updated;
}

1;
__END__
