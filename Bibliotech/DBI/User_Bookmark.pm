package Bibliotech::User_Bookmark;
use strict;
use base 'Bibliotech::DBI';
use Storable qw(dclone);

__PACKAGE__->table('user_bookmark');
#__PACKAGE__->columns(All => qw/user_bookmark_id user bookmark citation user_is_author
#		               private private_gang private_until created updated/);
__PACKAGE__->columns(Primary => qw/user_bookmark_id/);
__PACKAGE__->columns(Essential => qw/user bookmark updated citation user_is_author def_public private private_gang private_until quarantined created/);
#__PACKAGE__->columns(Others => qw/citation user_is_author private private_gang private_until created/);
__PACKAGE__->columns(TEMP => qw/user_bookmarks_count comments_count bookmark_is_linked_by_current_user tags_packed is_geotagged/);
# user_is_author a.k.a. mywork
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->datetime_column('updated', 'before_update');
__PACKAGE__->datetime_column('private_until');
__PACKAGE__->has_a(user => 'Bibliotech::User');
__PACKAGE__->has_a(bookmark => 'Bibliotech::Bookmark', inflate => \&make_bookmark);
__PACKAGE__->has_a(citation => 'Bibliotech::Citation');
__PACKAGE__->has_a(private_gang => 'Bibliotech::Gang');
__PACKAGE__->has_many(tags_raw => ['Bibliotech::User_Bookmark_Tag' => 'tag']);
__PACKAGE__->might_have(details => 'Bibliotech::User_Bookmark_Details' => qw/title description/);
__PACKAGE__->has_many(user_bookmark_comments => 'Bibliotech::User_Bookmark_Comment');
__PACKAGE__->has_many(comments => ['Bibliotech::User_Bookmark_Comment' => 'comment']);

sub is_mine {
  my ($self, $user) = @_;
  $user ||= $Bibliotech::Apache::USER_ID;
  my $user_id = UNIVERSAL::isa($user, 'Bibliotech::User') ? $user->user_id : $user;
  return $self->user->user_id == $user_id;
}

sub is_bookmark_also_mine {
  my ($self, $user) = @_;
  $user ||= $Bibliotech::Apache::USER_ID;
  return $self->bookmark->is_linked_by($user);
}

sub my_alias {
  'ub';
}

__PACKAGE__->set_sql(packed_query_using_subselect => <<'');
SELECT %s
FROM %s AS ubp
LEFT JOIN user_bookmark ub ON (ubp.user_bookmark_id=ub.user_bookmark_id)
LEFT JOIN user u ON (ub.user=u.user_id)
LEFT JOIN user_bookmark_tag ubt2 ON (ub.user_bookmark_id=ubt2.user_bookmark)
LEFT JOIN tag t2 ON (ubt2.tag=t2.tag_id)
LEFT JOIN user_bookmark_details ubd ON (ub.user_bookmark_id=ubd.user_bookmark_id)
LEFT JOIN citation ct ON (ub.citation=ct.citation_id)
LEFT JOIN citation_author cta ON (ct.citation_id=cta.citation)
LEFT JOIN author a ON (cta.author=a.author_id)
LEFT JOIN journal j ON (ct.journal=j.journal_id)
LEFT JOIN bookmark b ON (ub.bookmark=b.bookmark_id)
LEFT JOIN bookmark_details bd ON (b.bookmark_id=bd.bookmark_id)
LEFT JOIN citation ct2 ON (b.citation=ct2.citation_id)
LEFT JOIN citation_author cta2 ON (ct2.citation_id=cta2.citation)
LEFT JOIN author a2 ON (cta2.author=a2.author_id)
LEFT JOIN journal j2 ON (ct2.journal=j2.journal_id)
LEFT JOIN user_gang ug ON (u.user_id=ug.user)
LEFT JOIN gang g ON (ug.gang=g.gang_id)
LEFT JOIN bookmark b2 ON (ub.bookmark=b2.bookmark_id)
LEFT JOIN user_bookmark ub2 ON (b2.bookmark_id=ub2.bookmark AND %s)
LEFT JOIN user_bookmark_comment ubc2 ON (ub2.user_bookmark_id=ubc2.user_bookmark)
LEFT JOIN comment c2 ON (ubc2.comment=c2.comment_id)
LEFT JOIN user_bookmark ub3 ON (ubc2.user_bookmark=ub3.user_bookmark_id AND ub3.user = ?)
LEFT JOIN user_bookmark_tag ubt4 ON (ub.user_bookmark_id=ubt4.user_bookmark)
LEFT JOIN tag t4 ON (ubt4.tag=t4.tag_id AND t4.name = 'geotagged')
WHERE ub.user_bookmark_id IS NOT NULL
GROUP BY ubp.user_bookmark_id
%s

sub psql_packed_query_using_subselect {
  my ($self, $select, $subselect, $privacywhere, $sort) = @_;
  # Bibliotech::Query::privacywhere() generates a SQL snippet
  # that refers only to the 'ub' alias and here we want to influence
  # joining of the 'ub2' alias...
  $privacywhere =~ s/ub\./ub2\./g;
  return $self->sql_packed_query_using_subselect($select, $subselect, $privacywhere, $sort);
}

__PACKAGE__->set_sql(packed_count_query_using_subselect => <<'');
SELECT COUNT(*)
FROM (%s) AS ubp
LEFT JOIN user_bookmark ub ON (ubp.user_bookmark_id=ub.user_bookmark_id)
WHERE ub.user_bookmark_id IS NOT NULL

sub psql_packed_count_query_using_subselect {
  my ($self, $subselect) = @_;
  return $self->sql_packed_count_query_using_subselect($subselect);
}

sub packed_select {
  our @PACKED_SELECT;
  return @{dclone(\@PACKED_SELECT)} if @PACKED_SELECT;
  @PACKED_SELECT =
      (Bibliotech::DBI::packing_essentials('Bibliotech::User_Bookmark'),
       Bibliotech::DBI::packing_essentials('Bibliotech::User'),
       Bibliotech::DBI::packing_groupconcat('Bibliotech::Gang', undef, '_u_gangs_packed', 'ug.created'),
       Bibliotech::DBI::packing_essentials('Bibliotech::Bookmark'),
       Bibliotech::DBI::packing_essentials('Bibliotech::User_Bookmark_Details'),
       Bibliotech::DBI::packing_essentials('Bibliotech::Bookmark_Details'),
       Bibliotech::DBI::packing_essentials('Bibliotech::Citation'),
       Bibliotech::DBI::packing_essentials('Bibliotech::Journal'),
       Bibliotech::DBI::packing_essentials('Bibliotech::Citation_Author'),
       Bibliotech::DBI::packing_groupconcat('Bibliotech::Author', undef, '_ct_authors_packed', 'cta.displayorder'),
       Bibliotech::DBI::packing_essentials('Bibliotech::Citation', 'ct2'),
       Bibliotech::DBI::packing_essentials('Bibliotech::Journal', 'j2'),
       Bibliotech::DBI::packing_essentials('Bibliotech::Citation_Author', 'cta2'),
       Bibliotech::DBI::packing_groupconcat('Bibliotech::Author', 'a2', '_ct2_authors_packed', 'cta2.displayorder'),
       Bibliotech::DBI::packing_groupconcat('Bibliotech::Tag', 't2', '_ub_tags_packed', 'ubt2.created'),
       'COUNT(DISTINCT ub2.user_bookmark_id) as _ub_user_bookmarks_count',
       'COUNT(DISTINCT c2.comment_id) as _ub_comments_count',
       'COUNT(DISTINCT ub3.user_bookmark_id) as _ub_bookmark_is_linked_by_current_user',
       'COUNT(DISTINCT t4.tag_id) as _ub_is_geotagged');
  return @{dclone(\@PACKED_SELECT)};
}

sub select2names {
  my $select_ref = pop;
  my @names;
  foreach (@{$select_ref}) {
    if (/ [Aa][Ss] (\w+)$/) {
      my $field = $1;
      $field =~ s/^_([a-zA-Z0-9]+)_/$1./;
      $field =~ s/^(?!\w+\.)/ub./;
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

  my $user_bookmark_data = &{$filter}(ref $self || $self, undef, 1);

  $user_bookmark_data->{bookmark_is_linked_by_current_user}
    = [$Bibliotech::Apache::USER_ID, $user_bookmark_data->{bookmark_is_linked_by_current_user}]
	if defined $user_bookmark_data->{bookmark_is_linked_by_current_user};

  $user_bookmark_data->{bookmark}
    = &{$filter}('Bibliotech::Bookmark', undef, undef,
		 {citation => &{$filter}('Bibliotech::Citation', 'ct2', undef,
					 {journal => &{$filter}('Bibliotech::Journal', 'j2')})});

  $user_bookmark_data->{bookmark}->{_details_object} = &{$filter}('Bibliotech::Bookmark_Details');

  $user_bookmark_data->{user} = &{$filter}('Bibliotech::User');

  $user_bookmark_data->{citation} = &{$filter}('Bibliotech::Citation', undef, undef,
					       {journal => &{$filter}('Bibliotech::Journal')});

  my $obj = $self->construct($user_bookmark_data);
  $obj->{_details_object} = &{$filter}('Bibliotech::User_Bookmark_Details');
  $obj->bookmark->for_user_bookmark($obj);

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

# delete a user_bookmark
# delete the bookmark if no more user_bookmarks to it remain
# delete the citation if no more bookmarks or user_bookmarks to it remain
# delete each tag which has no more user_bookmarks to it remaining
# do not delete the user ;-)
# mark the user updated and mark his/her last_deletion
# mark the bookmark updated if it remained
sub delete {
  #warn 'delete user_bookmark';
  my $self     = shift;
  my $user     = $self->user;
  my $bookmark = $self->bookmark;
  my $citation = $self->citation;
  my @tags     = $self->tags;

  $self->SUPER::delete(@_);

  my $bookmark_count = $bookmark->user_bookmarks->count;

  $bookmark->delete unless $bookmark_count;
  $citation->delete if $citation and !$citation->bookmarks_or_user_bookmarks_count;

  foreach my $tag (@tags) {
    $tag->delete unless $tag->bookmarks->count;
  }

  $user->last_deletion_now;
  $user->mark_updated;
  $bookmark->mark_updated if $bookmark_count;
}

sub gangs {
  shift->user->gangs;
}

sub make_bookmark {
  my ($bookmark_id, $self) = @_;
  return $bookmark_id if UNIVERSAL::isa($bookmark_id, 'Bibliotech::Bookmark');
  my $bookmark = Bibliotech::Bookmark->retrieve($bookmark_id) or return undef;
  $bookmark->for_user_bookmark($self);
  return $bookmark;
}

sub link_tag {
  my $self = shift;
  my @ubt = 
      map(Bibliotech::User_Bookmark_Tag->find_or_create({user_bookmark => $self, tag => Bibliotech::Tag->new($_, 1)}), @_);
  return wantarray ? @ubt : $ubt[0];
}

sub unlink_tag {
  my $self = shift;
  foreach (@_) {
    my $tag = Bibliotech::Tag->new($_) or next;
    my ($link) = Bibliotech::User_Bookmark_Tag->search(user_bookmark => $self, tag => $tag) or next;
    $link->delete;
    $tag->delete unless $tag->bookmarks->count;
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

sub last_user_bookmark_comment {
  my $self = shift;
  my $iterator = $self->user_bookmark_comments or return undef;
  my $last = $iterator->count - 1;
  my ($user_bookmark_comment) = $iterator->slice($last, $last);
  return $user_bookmark_comment;
}

sub link_comment {
  my $self = shift;
  my @ubc = 
      map(Bibliotech::User_Bookmark_Comment->find_or_create({user_bookmark => $self, comment => Bibliotech::Comment->new($_, 2)}), @_);
  return wantarray ? @ubc : $ubc[0];
}

sub unlink_comment {
  my $self = shift;
  foreach (@_) {
    my $comment = Bibliotech::Comment->new($_) or next;
    my ($link) = Bibliotech::User_Bookmark_Comment->search(user_bookmark => $self, comment => $comment) or next;
    $link->delete;
  }
}

sub label {
  my ($self) = @_;
  return $self->user->label.' -> '.$self->bookmark->label.' ['.join(',', map($_->name, $self->tags)).']';
}

sub label_title {  # used for RSS description
  shift->bookmark->label_title(@_);
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
  my $bookmark          = $self->bookmark;
  my $bookmark_citation = $bookmark->citation;

  my @data = ([user_bookmark_id => $self->user_bookmark_id],
              [user_id          => $user->user_id],
              [bookmark_id      => $bookmark->bookmark_id],
              ['u citation_id'  => (defined $citation          ? $citation->citation_id          : '')],
              ['b citation_id'  => (defined $bookmark_citation ? $bookmark_citation->citation_id : '')],
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
  # if there is no id, avoid caching as its an ephemeral object, and without an id it is hard to make a key
  # if the debug flag is added, avoid cache as well
  if (my $user_bookmark_id = $self->user_bookmark_id and !$debug) {
    $memcache = $bibliotech->memcache;
    my $activeuser = $bibliotech->user;
    my $openurl = defined $activeuser ? $activeuser->openurl_cache_key || 'noopenurl' : 'noopenurl';
    $cache_key = Bibliotech::Cache::Key->new($bibliotech,
					     class => __PACKAGE__,
					     method => 'html_content',
					     id => $user_bookmark_id,
					     id => defined $activeuser ? 'logged-in' : 'visitor',
					     id => $openurl,
					     effective => [undef, $self->user],
					     options => {class => $class, verbose => $verbose, main => $main},
					     value => [bookmark => @{$command->bookmark || []} ? 'y' : 'n']);
    #$bibliotech->log->debug("$self updated: ".$self->updated->epoch);
    my $last_updated_obj = Bibliotech::Date->latest([$self->created,
						     $self->updated,
						     $self->bookmark->updated,
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
    my $count = do { my $stored_count = $self->user_bookmarks_count;
		     defined $stored_count ? $stored_count
			                   : $bookmark->user_bookmarks->count;
		   };
    if (defined $count and $count > 1) {
      $count--;
      if ($in_html) {
	$user_count_report = 'and '.$cgi->a({href => $bookmark->href_search_global($bibliotech)},
					    $count . ($count == 1 ? ' other' : ' others'));
      }
      else {
	$user_count_report = "and $count" . ($count == 1 ? ' other' : ' others');
      }
    }
    $count = $self->comments_count;
    $count = 0, map($count += $_->comments->count, $bookmark->user_bookmarks) unless defined $count;
    if ($count) {
      $user_count_report .= ' ' if $user_count_report;
      if ($in_html) {
	$user_count_report .= 'with '.$cgi->a({href => $bibliotech->location.'comments/uri/'.$bookmark->hash},
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
    push @posted, ('|',
		   $self->privacy_status_html($bibliotech),
		   $cgi->a({href => $bookmark->href_search_global($bibliotech)}, 'info'));
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

__PACKAGE__->set_sql(from_bookmark_for_user => <<'');
SELECT 	 __ESSENTIAL(ub)__
FROM     __TABLE(Bibliotech::User_Bookmark=ub)__
WHERE  	 ub.bookmark = ?
AND      ub.user = ?
ORDER BY ub.created

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
  return $bibliotech->cgi->span({class => 'private'}, @private).' | ';
}

sub is_any_privacy_active {
  my $self = shift;
  return 1 if $self->quarantined;
  return 0 if $self->private_until_status eq 'expired';
  return 1 if $self->private;
  return 1 if $self->private_gang;
  return 0;
}

# this needs to be customized for User_Bookmark because it's a dual one using two filters
sub href_search_global {
  my ($self, $bibliotech, $extras_ref) = @_;
  die 'no bibliotech object' unless $bibliotech;
  my $user           = $self->user;
  my $user_key       = $self->filter_name_to_label($user->search_key);
  my $user_value     = $user->search_value;
  my $bookmark       = $self->bookmark;
  my $bookmark_key   = $self->filter_name_to_label($bookmark->search_key);
  my $bookmark_value = $bookmark->search_value;
  my $uri            = join('/', $user_key, $user_value, $bookmark_key, $bookmark_value);
  return $self->href_with_extras($bibliotech, $uri, $extras_ref);
}

1;
__END__
