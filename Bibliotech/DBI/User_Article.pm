package Bibliotech::User_Article;
use strict;
use base 'Bibliotech::DBI';
use Storable qw(dclone);
use Bibliotech::Cache;

__PACKAGE__->table('user_article');
__PACKAGE__->columns(Primary => qw/user_article_id/);
__PACKAGE__->columns(Essential => qw/user article bookmark updated citation user_is_author def_public
                                     private private_gang private_until quarantined created/);
__PACKAGE__->columns(TEMP => qw/user_articles_count comments_count article_is_linked_by_current_user
                                tags_packed is_geotagged/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->datetime_column('updated', 'before_update');
__PACKAGE__->datetime_column('private_until');
__PACKAGE__->has_a(user => 'Bibliotech::User');
__PACKAGE__->has_a(article => 'Bibliotech::Article', inflate => \&make_article);
__PACKAGE__->has_a(bookmark => 'Bibliotech::Bookmark');
__PACKAGE__->has_a(citation => 'Bibliotech::Citation');
__PACKAGE__->has_a(private_gang => 'Bibliotech::Gang');
__PACKAGE__->has_many(tags_raw => ['Bibliotech::User_Article_Tag' => 'tag']);
__PACKAGE__->might_have(details => 'Bibliotech::User_Article_Details' => qw/title description/);
__PACKAGE__->has_many(user_article_comments => 'Bibliotech::User_Article_Comment');
__PACKAGE__->has_many(comments => ['Bibliotech::User_Article_Comment' => 'comment']);

sub is_mine {
  my ($self, $user) = @_;
  $user ||= $Bibliotech::Apache::USER_ID;
  my $user_id = UNIVERSAL::isa($user, 'Bibliotech::User') ? $user->user_id : $user;
  return $self->user->user_id == $user_id;
}

sub is_article_also_mine {
  my ($self, $user) = @_;
  $user ||= $Bibliotech::Apache::USER_ID;
  return $self->article->is_linked_by($user);
}

sub my_alias {
  'ua';
}

sub bookmarks {
  shift->article->bookmarks;
}

__PACKAGE__->set_sql(packed_query_using_subselect => <<'');
SELECT %s
FROM %s AS uap
LEFT JOIN user_article ua ON (uap.user_article_id=ua.user_article_id)
LEFT JOIN user u ON (ua.user=u.user_id)
LEFT JOIN user_article_tag uat2 ON (ua.user_article_id=uat2.user_article)
LEFT JOIN tag t2 ON (uat2.tag=t2.tag_id)
LEFT JOIN user_article_details uad ON (ua.user_article_id=uad.user_article_id)
LEFT JOIN citation ct ON (ua.citation=ct.citation_id)
LEFT JOIN citation_author cta ON (ct.citation_id=cta.citation)
LEFT JOIN author au ON (cta.author=au.author_id)
LEFT JOIN journal j ON (ct.journal=j.journal_id)
LEFT JOIN article a ON (ua.article=a.article_id)
LEFT JOIN bookmark b ON (ua.bookmark=b.bookmark_id)
LEFT JOIN bookmark_details bd ON (b.bookmark_id=bd.bookmark_id)
LEFT JOIN citation ct2 ON (a.citation=ct2.citation_id)
LEFT JOIN citation_author cta2 ON (ct2.citation_id=cta2.citation)
LEFT JOIN author au2 ON (cta2.author=au2.author_id)
LEFT JOIN journal j2 ON (ct2.journal=j2.journal_id)
LEFT JOIN user_gang ug ON (u.user_id=ug.user)
LEFT JOIN gang g ON (ug.gang=g.gang_id)
LEFT JOIN article a2 ON (ua.article=a2.article_id)
LEFT JOIN user_article ua2 ON (a2.article_id=ua2.article AND %s)
LEFT JOIN user_article_comment uac2 ON (ua2.user_article_id=uac2.user_article)
LEFT JOIN comment c2 ON (uac2.comment=c2.comment_id)
LEFT JOIN user_article ua3 ON (uac2.user_article=ua3.user_article_id AND ua3.user = ?)
LEFT JOIN user_article_tag uat4 ON (ua.user_article_id=uat4.user_article)
LEFT JOIN tag t4 ON (uat4.tag=t4.tag_id AND t4.name = 'geotagged')
WHERE ua.user_article_id IS NOT NULL
GROUP BY uap.user_article_id
%s

sub psql_packed_query_using_subselect {
  my ($self, $select, $subselect, $privacywhere, $sort) = @_;
  $privacywhere =~ s/ua\./ua2\./g;
  return $self->sql_packed_query_using_subselect($select, $subselect, $privacywhere, $sort);
}

__PACKAGE__->set_sql(packed_count_query_using_subselect => <<'');
SELECT COUNT(*)
FROM (%s) AS uap
LEFT JOIN user_article ua ON (uap.user_article_id=ua.user_article_id)
WHERE ua.user_article_id IS NOT NULL

sub psql_packed_count_query_using_subselect {
  my ($self, $subselect) = @_;
  return $self->sql_packed_count_query_using_subselect($subselect);
}

sub packed_select {
  our @PACKED_SELECT;
  return @{dclone(\@PACKED_SELECT)} if @PACKED_SELECT;
  @PACKED_SELECT =
      (Bibliotech::DBI::packing_essentials('Bibliotech::User_Article'),
       Bibliotech::DBI::packing_essentials('Bibliotech::User'),
       Bibliotech::DBI::packing_groupconcat('Bibliotech::Gang', undef, '_u_gangs_packed', 'ug.created'),
       Bibliotech::DBI::packing_essentials('Bibliotech::Article'),
       Bibliotech::DBI::packing_essentials('Bibliotech::Bookmark'),
       Bibliotech::DBI::packing_essentials('Bibliotech::User_Article_Details'),
       Bibliotech::DBI::packing_essentials('Bibliotech::Bookmark_Details'),
       Bibliotech::DBI::packing_essentials('Bibliotech::Citation'),
       Bibliotech::DBI::packing_essentials('Bibliotech::Journal'),
       Bibliotech::DBI::packing_groupconcat('Bibliotech::Author', undef, '_ct_authors_packed', 'cta.displayorder'),
       Bibliotech::DBI::packing_essentials('Bibliotech::Citation', 'ct2'),
       Bibliotech::DBI::packing_essentials('Bibliotech::Journal', 'j2'),
       Bibliotech::DBI::packing_groupconcat('Bibliotech::Author', 'au2', '_ct2_authors_packed', 'cta2.displayorder'),
       Bibliotech::DBI::packing_groupconcat('Bibliotech::Tag', 't2', '_ua_tags_packed', 'uat2.created'),
       'COUNT(DISTINCT ua2.user_article_id) as _ua_user_articles_count',
       'COUNT(DISTINCT c2.comment_id) as _ua_comments_count',
       'COUNT(DISTINCT ua3.user_article_id) as _ua_article_is_linked_by_current_user',
       'COUNT(DISTINCT t4.tag_id) as _ua_is_geotagged');
  return @{dclone(\@PACKED_SELECT)};
}

sub select2names {
  my $select_ref = pop;
  my @names;
  foreach (@{$select_ref}) {
    if (/ [Aa][Ss] (\w+)$/) {
      my $field = $1;
      $field =~ s/^_([a-zA-Z0-9]+)_/$1./;
      $field =~ s/^(?!\w+\.)/ua./;
      push @names, $field;
    }
    else {
      my $field = $_;
      $field =~ s/^[A-Z]+\((.*)\)$/$1/;  # MAX()
      push @names, $field;
    }
  }
  return bless \@names, 'Bibliotech::DBI::PackedSelectNames';
}

sub unpack_packed_select {
  my ($self, $select_ref, $data_ref) = @_;

  my $names_ref = ref $select_ref eq 'Bibliotech::DBI::PackedSelectNames' ? $select_ref : select2names($select_ref);

  my $filter = sub { ups_filter($names_ref, $data_ref, @_) };

  my $user_article_data = &{$filter}(ref $self || $self, undef, 1);

  $user_article_data->{article_is_linked_by_current_user}
    = [$Bibliotech::Apache::USER_ID, $user_article_data->{article_is_linked_by_current_user}]
	if defined $user_article_data->{article_is_linked_by_current_user};

  $user_article_data->{article} = &{$filter}('Bibliotech::Article');

  $user_article_data->{bookmark}
    = &{$filter}('Bibliotech::Bookmark', undef, undef,
		 {citation => &{$filter}('Bibliotech::Citation', 'ct2', undef,
					 {journal => &{$filter}('Bibliotech::Journal', 'j2')})});

  $user_article_data->{bookmark}->{_details_object} = &{$filter}('Bibliotech::Bookmark_Details');

  $user_article_data->{user} = &{$filter}('Bibliotech::User');

  $user_article_data->{citation} = &{$filter}('Bibliotech::Citation', undef, undef,
					       {journal => &{$filter}('Bibliotech::Journal')});

  my $obj = $self->construct($user_article_data);
  $obj->{_details_object} = &{$filter}('Bibliotech::User_Article_Details');

  $obj->article->for_user_article($obj);
  $obj->bookmark->for_user_article($obj);

  delete $obj->article->{__Changed};
  delete $obj->bookmark->{__Changed};
  delete $obj->{__Changed};

  return $obj;
}

sub ups_filter {
  my ($names_ref, $data_ref, $class, $alias, $just_data, $override_data_ref) = @_;
  my @names = @{$names_ref};
  $alias ||= $class->my_alias;
  my $ualias = '_'.$alias.'_';
  my %data = defined $override_data_ref ? %{$override_data_ref} : ();
  foreach (0 .. $#names) {
    if ($names[$_] =~ /^($alias\.|$ualias)(.+)$/) {
      $data{$2} = $data_ref->[$_] unless exists $data{$2};
    }
  }
  return \%data if $just_data;
  return %data ? $class->construct(\%data) : undef;
}

sub tags {
  shift->packed_or_raw('Bibliotech::Tag', 'tags_packed', 'tags_raw');
}

# delete a user_article
# delete the article if no more user_articles to it remain
# delete the citation if no more articles or user_articles to it remain
# delete each tag which has no more user_articles to it remaining
# do not delete the user ;-)
# mark the user updated and mark his/her last_deletion
# mark the article updated if it remained
sub delete {
  my $self     = shift;
  my $user     = $self->user;
  my $bookmark = $self->bookmark;
  my $article  = $self->article;
  my $citation = $self->citation;
  my @tags     = $self->tags;

  $self->bookmark(undef);
  $self->update;

  $self->SUPER::delete(@_);

  $bookmark->delete if $bookmark->user_articles_raw->count == 0;

  my $article_count = $article->user_articles->count;

  $article->delete if $article_count == 0;

  $citation->delete if $citation and $citation->bookmarks_or_user_articles_or_articles_count == 0;

  foreach my $tag (@tags) {
    $tag->delete unless $tag->user_articles->count;
  }

  if ($article_count > 0) {
    $article->mark_updated;
    $article->reconcat_citations;
  }

  $user->last_deletion_now;
  $user->mark_updated;
}

sub gangs {
  shift->user->gangs;
}

sub make_article {
  my ($article_id, $self) = @_;
  return $article_id if UNIVERSAL::isa($article_id, 'Bibliotech::Article');
  my $article = Bibliotech::Article->retrieve($article_id) or return undef;
  $article->for_user_article($self);
  return $article;
}

sub link_tag {
  my $self = shift;
  my @uat = 
      map(Bibliotech::User_Article_Tag->find_or_create({user_article => $self, tag => Bibliotech::Tag->new($_, 1)}), @_);
  return wantarray ? @uat : $uat[0];
}

sub unlink_tag {
  my $self = shift;
  foreach (@_) {
    my $tag = Bibliotech::Tag->new($_) or next;
    my ($link) = Bibliotech::User_Article_Tag->search(user_article => $self, tag => $tag) or next;
    $link->delete;
    $tag->delete unless $tag->count_active;
  }
}

sub last_comment {
  my $self = shift;
  my $iterator = $self->comments or return undef;
  my $last = $iterator->count - 1;
  my ($comment) = $iterator->slice($last, $last);
  return $comment;
}

sub update_last_comment {
  my ($self, $text) = @_;
  my $comment = $self->last_comment or return undef;
  $comment->entry($text);
  $comment->update;
  return $comment;
}

sub last_user_article_comment {
  my $self = shift;
  my $iterator = $self->user_article_comments or return undef;
  my $last = $iterator->count - 1;
  my ($user_article_comment) = $iterator->slice($last, $last);
  return $user_article_comment;
}

sub link_comment {
  my $self = shift;
  my @uac = 
      map(Bibliotech::User_Article_Comment->find_or_create({user_article => $self, comment => Bibliotech::Comment->new($_, 2)}), @_);
  return wantarray ? @uac : $uac[0];
}

sub unlink_comment {
  my $self = shift;
  foreach (@_) {
    my $comment = Bibliotech::Comment->new($_) or next;
    my ($link) = Bibliotech::User_Article_Comment->search(user_article => $self, comment => $comment) or next;
    $link->delete;
  }
}

sub bookmark_or_article_label {
  my $self = shift;
  if (defined (my $bookmark = $self->bookmark)) {
    return $bookmark->label;
  }
  return $self->article->label;
}

sub label {
  my $self = shift;
  return $self->user->label.' -> '.$self->bookmark_or_article_label.' ['.join(',', map($_->name, $self->tags)).']';
}

sub label_title {  # used for RSS description
  shift->article->label_title(@_);
}

sub tt_content {
  my $self = shift;
  return $self->id;
}

sub debug_html_content {
  my $self              = shift;
  my $bibliotech        = shift;
  my $citation          = $self->citation;
  my $user              = $self->user;
  my $article          = $self->article;
  my $article_citation = $article->citation;

  my @data = ([user_article_id => $self->user_article_id],
              [user_id          => $user->user_id],
              [article_id      => $article->article_id],
              ['u citation_id'  => (defined $citation          ? $citation->citation_id          : '')],
              ['b citation_id'  => (defined $article_citation ? $article_citation->citation_id : '')],
	      [sortvalue        => $self->sortvalue],
              );

  return $bibliotech->cgi->div({class => 'debug'}, join(', ', map { $_->[0].'='.($_->[1]||'') } @data));
}

sub html_content {
  my ($self, $bibliotech, $class, $verbose, $main) = @_;

  my $command = $bibliotech->command;
  my $cgi = $bibliotech->cgi;
  my $debug = $cgi->param('debug') ? 1 : 0;

  my ($memcache, $cache_key, $last_updated);
  my $memcache = $bibliotech->memcache;
  # if there is no id, avoid caching as its an ephemeral object, and without an id it is hard to make a key
  # if the debug flag is added, avoid cache as well
  if (my $user_article_id = $self->user_article_id and !$debug and $memcache) {
    my $activeuser = $bibliotech->user;
    my $openurl = defined $activeuser ? $activeuser->openurl_cache_key || 'noopenurl' : 'noopenurl';
    $cache_key = Bibliotech::Cache::Key->new($bibliotech,
					     class => __PACKAGE__,
					     method => 'html_content',
					     id => $user_article_id,
					     id => defined $activeuser ? 'logged-in' : 'visitor',
					     id => $openurl,
					     effective => [undef, $self->user],
					     options => {class => $class, verbose => $verbose, main => $main},
					     value => [bookmark => @{$command->bookmark || []} ? 'y' : 'n']);
    #$bibliotech->log->debug("$self updated: ".$self->updated->epoch);
    my $last_updated_obj = Bibliotech::Date->latest([$self->created,
						     $self->updated,
						     $self->article->updated,
						     $self->private_until,
						     defined $activeuser ? $activeuser->updated : undef],
						    only_current => 1,
						    );
						    #log => $bibliotech->log);
    if (defined $last_updated_obj) {
      # it's possible that it won't be defined if the database produced future values
      # which can happen easily if the database is on another server
      $last_updated = $last_updated_obj->epoch;
    }
    my $cache_entry = $memcache->get_with_last_updated($cache_key, $last_updated, undef, 1);
    return wantarray ? @{$cache_entry} : join('', @{$cache_entry}) if defined $cache_entry;
  }

  my @output = $self->html_content_calc($bibliotech, $class, $verbose, $main);

  $memcache->set_with_last_updated($cache_key => \@output, $last_updated) if $memcache;
  return wantarray ? @output : join('', @output);
}

sub html_content_calc {
  my ($self, $bibliotech, $class, $verbose, $main) = @_;

  my $bookmark              = $self->bookmark or die 'no bookmark';
  my $bookmark_html_content = $bookmark->html_content($bibliotech, $class, $verbose, $main);
  my $cgi    		    = $bibliotech->cgi;
  my $debug  		    = $cgi->param('debug') ? 1 : 0;
  my @output 		    = ($debug ? $self->debug_html_content($bibliotech) : (),
			       $bookmark_html_content);

  if ($verbose) {
    push @output, $self->postedby(bibliotech => $bibliotech, main => $main, html => 1);
    my $comments = $self->comments_html($bibliotech);
    push @output, $comments if $comments;
  }

  return wantarray ? @output : join('', @output);
}

sub comments_html {
  my ($self, $bibliotech) = @_;
  die 'no bibliotech object' unless $bibliotech;
  my $command = $bibliotech->command;
  if ($command->is_bookmark_command) {
    my $verbose_comments = $command->page =~ /comments/;
    my @comments = map($_->html_content($bibliotech, 'comment', $verbose_comments, 1), $self->comments);
    return $bibliotech->cgi->div({class => 'comments'}, @comments) if @comments;
  }
  return;
}

sub postedby {
  my ($self, %options) = @_;
  my $bibliotech = $options{bibliotech} or die 'must pass in bibliotech object';
  my $article = $self->article;
  my $bookmark = $self->bookmark;
  my $adding = $bookmark->adding;
  return wantarray ? () : '' if $adding >= 4;
  my $main = $options{main};
  my $cgi = $bibliotech->cgi;
  my $show_counts = defined $options{show_counts} ? $options{show_counts} : ($adding ? 0 : 1);
  my $in_html = $options{html} ? 1 : 0;
  my @tags = defined $options{tags} ? @{$options{tags}} : $self->tags;
  my $quote_tags = defined $options{quote_tags} ? $options{quote_tags} : (!$in_html || $adding >= 3);
  my @output;

  if (my $description = $self->description) {
    push @output, ($in_html
		   ? $cgi->div({class => 'description'}, Bibliotech::Util::encode_xhtml_utf8($description))
		   : "\"$description\"");
  }

  my $user_count_report = '';
  if ($show_counts) {
    my $count = do { my $stored_count = $self->user_articles_count;
		     defined $stored_count ? $stored_count
			                   : $article->user_articles->count;
		   };
    if (defined $count and $count > 1) {
      $count--;
      if ($in_html) {
	$user_count_report = 'and '.$cgi->a({href => $article->href_search_global($bibliotech)},
					    $count . ($count == 1 ? ' other' : ' others'));
      }
      else {
	$user_count_report = "and $count" . ($count == 1 ? ' other' : ' others');
      }
    }
    $count = $self->comments_count;
    $count = 0, map($count += $_->comments->count, $article->user_articles) unless defined $count;
    if ($count) {
      $user_count_report .= ' ' if $user_count_report;
      if ($in_html) {
	$user_count_report .= 'with '.$cgi->a({href => $bibliotech->location.'comments/uri/'.$article->hash},
					      $count . ($count == 1 ? ' comment' : ' comments'));
      }
      else {
	$user_count_report .= "with $count" . ($count == 1 ? ' comment' : ' comments');
      }
    }
  }

  my @posted;

  my @postedby;
  push @postedby, $adding ? 'To be posted' : 'Posted';
  if (my $user = $self->user) {
    push @postedby, ('by',
		     $in_html
		     ? $user->link($bibliotech, 'postedby', $main ? 'href_search_global' : undef, undef, 1)
		     : $user->label);
    push @postedby, '(who is an author)' if $self->user_is_author;
  }
  push @postedby, $user_count_report if $user_count_report;
  if ($in_html) {
    push @posted, $cgi->span({class => 'postedby'}, @postedby);
  }
  else {
    push @posted, join(' ', @postedby);
  }

  if (@tags) {
    @tags = map(/ / ? "\"$_\"" : $_, @tags) if $quote_tags;
    if ($in_html) {
      my @taglinks;
      foreach (0 .. $#tags) {
	my $tag = $tags[$_];
	my $label = $tag->label;
	my $link = $tag->link($bibliotech, 'postedtag', $main ? 'href_search_global' : undef, undef, 1);
	$link = "\"$link\"" if $quote_tags and $label =~ / /;
	push @taglinks, $link;
      }
      @tags = @taglinks;
    }
    else {
      @tags = map($quote_tags && / / ? "\"$_\"" : $_, map($_->label, @tags));
    }
    if ($in_html) {
      push @posted, $cgi->span({class => 'postedtags'}, 'to', @tags);
    }
    else {
      push @posted, join(' ', 'to', @tags),
    }
  }

  if (my $created = $self->created) {
    if ($in_html) {
      push @posted, $cgi->span({class => 'postedtime'}, 'on',
			       $created->link($bibliotech, undef, $main ? 'href_search_global' : undef, undef, 1));
    }
    else {
      push @posted, join(' ', 'on', $created->label);
    }
  }

  if ($in_html) {
    push @posted, (do { local $_ = $self->privacy_status_html($bibliotech); $_ ? ('|', $_) : (); },
		   ($adding ? () : ('|', $cgi->a({href => $article->href_search_global($bibliotech)}, 'info'),
				    '|', _proxit_link($self->bookmark->url, $cgi))));
  }

  if (@posted) {
    if ($in_html) {
      push @output, $cgi->div({class => 'posted'}, @posted);
    }
    else {
      push @output, join(' ', @posted);
    }
  }

  return wantarray ? @output : join($in_html ? '' : ' ', @output);
}

sub _proxit_link {
  my ($url, $cgi) = @_;
  local $_ = $cgi->a({id      => '__ID__',
		      onclick => 'return false;',
		      title   => 'Results powered by Proximic',
		     },
		     'related');
  # avoid CGI.pm escaping of ampersand and actual URL by replacement after the fact:
  my $special_id = join('',
			'proximic_proxit:',                                                        # intro
			join('&',
			     'aid=npg',                                                            # aid
			     'headerURL=http://query.proximic.com/flash/images/logo_connotea.png', # headerURL
			     'channel_expand=BUECHER',                                             # channel_expand
			     'query_url='.$url));                                                  # the URL
  s/__ID__/$special_id/;
  return $_;
}

sub rss_content {
  my ($self, $bibliotech, $verbose) = @_;

  my $bookmark = $self->bookmark;
  my $user     = $self->user;
  my $location = $bibliotech->location;

  my %item = (title       => $bookmark->label_title,
	      link        => $bookmark->href_hash($bibliotech, {user => $user->username}),
	      description => scalar $self->postedby(bibliotech => $bibliotech, main => 1));

  if ($verbose) {
    $item{dc} = {date    => $self->created->iso8601_utc,
		 creator => $user->label};
    $item{dc}->{subject} = [map($_->label, $self->tags)] if $self->can('tags');
    if (my $html = $self->html_content($bibliotech, 'rssitem', 1, 1)) {
      my $style = "<link rel=\"stylesheet\" href=\"${location}global.css\" type=\"text/css\" title=\"styled\"/>";
      $item{content} = {encoded => "<![CDATA[$style$html]]>"};
    }
    $item{annotate} = {reference => $location.'comments/uri/'.$bookmark->hash};
    $item{slash}    = {comments  => $self->comments->count};
    $item{connotea} = {uri       => $bookmark->biblio_rdf($bibliotech)};
  }

  return wantarray ? %item : \%item;
}

sub txt_content {
  my ($self, $bibliotech, $verbose) = @_;
  return $self->bookmark->txt_content($bibliotech, $verbose);
}

sub ris_content {
  my ($self, $bibliotech, $verbose) = @_;
  return $self->bookmark->ris_content($bibliotech, $verbose, $self);
}

sub geo_content {
  my ($self, $bibliotech, $verbose) = @_;

  my $bookmark = $self->bookmark;
  my $cgi = $bibliotech->cgi;

  # scan tags, return undef on error
  my $geo = eval { return Bibliotech::SpecialTagSet::Geo->scan([$self->tags]); };
  die $@ if $@ =~ / at .* line /;
  return wantarray ? () : undef unless $geo;

  # create description text
  my $bookmark_link = $bookmark->link($bibliotech, 'geo', undef, undef, 1);
  my $description = $self->description;
  my $postedby = $self->postedby(bibliotech => $bibliotech, tags => $geo->rest, main => 1, html => 1);
  my $geo_description = join("\n",
			     map($cgi->p($_),
				 grep($_,
				      $bookmark_link,
				      $description,
				      $postedby)));

  my %item = (name        => $self->label_title,
	      description => $geo_description,
	      latitude    => $geo->latitude,
	      longitude   => $geo->longitude);

  return wantarray ? %item : \%item;
}

sub href {
  shift->bookmark->href(@_);
}

__PACKAGE__->set_sql(from_article_for_user => <<'');
SELECT 	 __ESSENTIAL(ua)__
FROM     __TABLE(Bibliotech::User_Article=ua)__
WHERE  	 ua.article = ?
AND      ua.user = ?
ORDER BY ua.created

sub count_active {
  shift->count_all;
}

# based on private_until, returns 'active', 'expired', or 'inactive'
sub private_until_status {
  if (defined(my $timestamp = shift->private_until)) {
    return $timestamp->has_been_reached ? 'expired' : 'active';
  }
  return 'inactive';
}

sub private_until_active {
  shift->private_until_status eq 'active';
}

sub privacy_status_html {
  my ($self, $bibliotech) = @_;
  die 'no bibliotech object' unless $bibliotech;
  my @private;
  push @private, 'quarantined' if $self->quarantined;
  my $embargo_date_status = $self->private_until_status;
  if ($embargo_date_status ne 'expired') {
    if ($self->private) {
      push @private, 'private';
    }
    elsif (my $private_gang = $self->private_gang) {
      push @private, ('private to', $private_gang->link($bibliotech, 'privateto'));
    }
  }
  return unless @private;
  push @private, ('until', scalar $self->private_until->label_plus_time) if $embargo_date_status eq 'active';
  return $bibliotech->cgi->span({class => 'private'}, @private);
}

sub is_any_privacy_active {
  my $self = shift;
  return 1 if $self->quarantined;
  return 0 if $self->private_until_status eq 'expired';
  return 1 if $self->private;
  return 1 if $self->private_gang;
  return 0;
}

# this needs to be customized for User_Article because it's a dual one using two filters
sub href_search_global {
  my ($self, $bibliotech, $extras_ref) = @_;
  die 'no bibliotech object' unless $bibliotech;
  my $user           = $self->user;
  my $user_key       = $self->filter_name_to_label($user->search_key);
  my $user_value     = $user->search_value;
  my $article        = $self->article;
  my $article_key    = $self->filter_name_to_label($article->search_key);
  my $article_value  = $article->search_value;
  my $uri            = join('/', $user_key, $user_value, $article_key, $article_value);
  return $self->href_with_extras($bibliotech, $uri, $extras_ref);
}

__PACKAGE__->set_sql(update_def_public_index => <<'');
UPDATE user_bookmark
SET    def_public = IF(private = 0 AND private_gang IS NULL AND private_until IS NULL AND quarantined IS NULL, 1, 0)

1;
__END__
