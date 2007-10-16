package Bibliotech::Tag;
use strict;
use base 'Bibliotech::DBI';
use Bibliotech::Query;

__PACKAGE__->table('tag');
#__PACKAGE__->columns(All => qw/tag_id name created/);
__PACKAGE__->columns(Primary => qw/tag_id/);
__PACKAGE__->columns(Essential => qw/name/);
__PACKAGE__->columns(Others => qw/created updated/);
__PACKAGE__->columns(TEMP => qw/memory_score memory_score_recency memory_score_frequency filtered_count filtered_user_count filtered_bookmark_count rss_date_override/);
__PACKAGE__->force_utf8_columns(qw/name/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->datetime_column('updated', 'before_update');
__PACKAGE__->has_many(user_bookmark_tags => 'Bibliotech::User_Bookmark_Tag');
__PACKAGE__->has_many(user_bookmarks => ['Bibliotech::User_Bookmark_Tag' => 'user_bookmark']);

sub my_alias {
  't';
}

sub unique {
  'name';
}

sub visit_link {
  my ($self, $bibliotech, $class) = @_;
  return $bibliotech->cgi->div({class => ($class || 'referent')},
			       'Go to the',
			       $bibliotech->sitename,
			       'page for the tag',
			       '"'.$self->link($bibliotech, undef, 'href_search_global', undef, 1).'".'
			       );
}

sub count_active {
  # use user_bookmark_tag table; it's faster
  Bibliotech::User_Bookmark_Tag->sql_single('COUNT(DISTINCT tag)')->select_val;
}

# call count_user_bookmarks() and the privacy parameter is handled for you
__PACKAGE__->set_sql(count_user_bookmarks_need_privacy => <<'');
SELECT 	 COUNT(DISTINCT ub.user_bookmark_id)
FROM     __TABLE(Bibliotech::User_Bookmark_Tag=ubt)__
         LEFT JOIN __TABLE(Bibliotech::User_Bookmark=ub)__ ON (__JOIN(ubt ub)__)
WHERE    ubt.tag = ? AND %s

sub count_user_bookmarks {
  my $self = shift;
  my ($privacywhere, @privacybind) = Bibliotech::Query->privacywhere($Bibliotech::Apache::USER);
  my $sth = $self->sql_count_user_bookmarks_need_privacy($privacywhere);
  $sth->execute($self, @privacybind);
  my ($count) = $sth->fetchrow_array;
  $sth->finish;
  return $count;
}

sub packed_select {
  my $self = shift;
  my $alias = $self->my_alias;
  return (map("$alias.$_", $self->_essential),
	  #'EXP((DATEDIFF(MAX(ubt.created),NOW())/3600*24)/COUNT(ubt.user_bookmark_tag_id)) as memory_score');
	  'EXP(((UNIX_TIMESTAMP(MAX(ubt.created))-UNIX_TIMESTAMP(NOW()))/3600)/COUNT(ubt.user_bookmark_tag_id)) as memory_score',
	  'COUNT(ubt.user_bookmark_tag_id) as filtered_count',
	  'COUNT(DISTINCT ub.user) as filtered_user_count',
	  'COUNT(DISTINCT ub.bookmark) as filtered_bookmark_count',
	  );
}

sub parse_ignore_list {
  my $ref = pop || ['uploaded'];
  $ref = [split(/,\s*/, $ref)] if ref $ref eq 'SCALAR';
  my @ignore = @{$ref};
  my $question_marks = join(', ', map('?', @ignore));
  return ($question_marks, @ignore);
}

# call search_for_tag_cloud() and the privacy parameter is handled for you
__PACKAGE__->set_sql(for_tag_cloud_need_privacy => <<'');
SELECT   __ESSENTIAL__,
         memory_score,
         memory_score_recency,
         memory_score_frequency
FROM
(
SELECT   __ESSENTIAL(t)__,
         EXP(((UNIX_TIMESTAMP(MAX(ubt.created))-UNIX_TIMESTAMP(NOW()))/3600)/COUNT(ubt.user_bookmark_tag_id)) as memory_score,
         (UNIX_TIMESTAMP(MAX(ubt.created))-UNIX_TIMESTAMP(NOW()))/3600 as memory_score_recency,
         COUNT(ubt.user_bookmark_tag_id) as memory_score_frequency
FROM   	 (SELECT user_bookmark_id FROM __TABLE(Bibliotech::User_Bookmark=ub)__ WHERE %s) AS ubi
       	 LEFT JOIN __TABLE(Bibliotech::User_Bookmark_Tag=ubt)__ ON __JOIN(ubi ubt)__
       	 LEFT JOIN __TABLE(Bibliotech::Tag=t)__ ON __JOIN(ubt t)__
GROUP BY t.tag_id
ORDER BY memory_score DESC
LIMIT    %s
) as ti
WHERE    name NOT IN (%s)
ORDER BY memory_score DESC
LIMIT    %s

sub search_for_tag_cloud {
  my ($self, $ignore_ref, $visitor) = @_;
  my $user = $visitor ? undef : $Bibliotech::Apache::USER;
  my ($privacywhere, @privacybind) = Bibliotech::Query->privacywhere($user);
  my ($ignore_question_marks, @ignore) = $self->parse_ignore_list($ignore_ref);
  my $sth = $self->sql_for_tag_cloud_need_privacy($privacywhere, 100 + @ignore, $ignore_question_marks, 100);
  return $self->sth_to_objects($sth, [@privacybind, @ignore]);
}

# call search_for_tag_cloud_in_window() and the privacy parameter is handled for you
__PACKAGE__->set_sql(for_tag_cloud_in_window_need_privacy => <<'');
SELECT   __ESSENTIAL__,
         memory_score,
         memory_score_recency,
         memory_score_frequency
FROM
(
SELECT   __ESSENTIAL(t)__,
         EXP(((UNIX_TIMESTAMP(MAX(ubt.created))-UNIX_TIMESTAMP(NOW()))/3600)/COUNT(ubt.user_bookmark_tag_id)) as memory_score,
         (UNIX_TIMESTAMP(MAX(ubt.created))-UNIX_TIMESTAMP(NOW()))/3600 as memory_score_recency,
         COUNT(ubt.user_bookmark_tag_id) as memory_score_frequency
FROM
(
SELECT   user_bookmark_id
FROM     __TABLE(Bibliotech::User_Bookmark)__
WHERE    created >= NOW() - INTERVAL %s
AND      created <= NOW() - INTERVAL %s
UNION
SELECT   user_bookmark_id
FROM     __TABLE(Bibliotech::User_Bookmark)__
WHERE    updated >= NOW() - INTERVAL %s
AND      updated <= NOW() - INTERVAL %s
) AS ubi
	 LEFT JOIN __TABLE(Bibliotech::User_Bookmark=ub)__ ON (ubi.user_bookmark_id=ub.user_bookmark_id AND %s)
       	 LEFT JOIN __TABLE(Bibliotech::User_Bookmark_Tag=ubt)__ ON (__JOIN(ub ubt)__)
         LEFT JOIN __TABLE(Bibliotech::Tag=t)__ ON (__JOIN(ubt t)__)
GROUP BY t.tag_id
ORDER BY memory_score DESC
LIMIT    %s
) AS ti
WHERE  	 name NOT IN (%s)
ORDER BY memory_score DESC
LIMIT    %s

sub search_for_tag_cloud_in_window {
  my ($self, $window_spec, $lag_spec, $ignore_ref, $visitor) = @_;
  my $window = $self->untaint_time_window_spec($window_spec);
  my $lag    = $self->untaint_time_window_spec($lag_spec);
  my $user   = $visitor ? undef : $Bibliotech::Apache::USER;
  my ($privacywhere, @privacybind) = Bibliotech::Query->privacywhere($user);
  my ($ignore_question_marks, @ignore) = $self->parse_ignore_list($ignore_ref);
  my $sth = $self->sql_for_tag_cloud_in_window_need_privacy($window => $lag,
							    $window => $lag,
							    $privacywhere,
							    100 + @ignore,
							    $ignore_question_marks,
							    100);
  return $self->sth_to_objects($sth, [@privacybind, @ignore]);
}

# call search_for_popular_tags_in_window() and the privacy parameter is handled for you
__PACKAGE__->set_sql(for_popular_tags_in_window_need_privacy => <<'');
SELECT   __ESSENTIAL__,
         filtered_count,
         filtered_user_count,
         filtered_bookmark_count,
         rss_date_override
FROM
(
SELECT   __ESSENTIAL(t)__,
         COUNT(ubt.user_bookmark_tag_id) as filtered_count,
         COUNT(DISTINCT ub.user) as filtered_user_count,
         COUNT(DISTINCT ub.bookmark) as filtered_bookmark_count,
         MAX(ubt.created) as rss_date_override
FROM
(
SELECT   user_bookmark_id
FROM     __TABLE(Bibliotech::User_Bookmark)__
WHERE    created >= NOW() - INTERVAL %s
AND      created <= NOW() - INTERVAL %s
UNION
SELECT   user_bookmark_id
FROM     __TABLE(Bibliotech::User_Bookmark)__
WHERE    updated >= NOW() - INTERVAL %s
AND      updated <= NOW() - INTERVAL %s
) AS ubi
	 LEFT JOIN __TABLE(Bibliotech::User_Bookmark=ub)__ ON (ubi.user_bookmark_id=ub.user_bookmark_id AND %s)
       	 LEFT JOIN __TABLE(Bibliotech::User_Bookmark_Tag=ubt)__ ON (__JOIN(ub ubt)__)
         LEFT JOIN __TABLE(Bibliotech::Tag=t)__ ON (__JOIN(ubt t)__)
GROUP BY t.tag_id
HAVING   filtered_count > filtered_user_count
AND      filtered_count >= ?
AND      filtered_user_count >= ?
AND      filtered_bookmark_count >= ?
ORDER BY filtered_count DESC
LIMIT    %s
) AS ti
WHERE  	 name NOT IN (%s)
ORDER BY filtered_count DESC
LIMIT    %s

sub search_for_popular_tags_in_window {
  my ($self, $window_spec, $lag_spec, $ignore_ref, $post_count_min, $user_count_min, $bookmark_count_min, $visitor, $limit_spec) = @_;
  my $window = $self->untaint_time_window_spec($window_spec);
  my $lag    = $self->untaint_time_window_spec($lag_spec);
  my $user   = $visitor ? undef : $Bibliotech::Apache::USER;
  my ($privacywhere, @privacybind) = Bibliotech::Query->privacywhere($user);
  my ($ignore_question_marks, @ignore) = $self->parse_ignore_list($ignore_ref);
  my $limit = $self->untaint_limit_spec($limit_spec || 100);
  my $sth = $self->sql_for_popular_tags_in_window_need_privacy($window => $lag,
							       $window => $lag,
							       $privacywhere,
							       $limit + @ignore,
							       $ignore_question_marks,
							       $limit);
  return $self->sth_to_objects($sth, [@privacybind, $post_count_min, $user_count_min, $bookmark_count_min, @ignore]);
}

sub users {
  return Bibliotech::User->search_from_tag(shift->tag_id);
}

sub bookmarks {
  return Bibliotech::Bookmark->search_from_tag(shift->tag_id);
}

__PACKAGE__->set_sql(from_user => <<'');
SELECT 	 __ESSENTIAL(c4)__
FROM   	 __TABLE(Bibliotech::User=c1)__,
       	 __TABLE(Bibliotech::User_Bookmark=c2)__,
       	 __TABLE(Bibliotech::User_Bookmark_Tag=c3)__,
       	 __TABLE(Bibliotech::Tag=c4)__
WHERE  	 __JOIN(c1 c2)__
AND    	 __JOIN(c2 c3)__
AND    	 __JOIN(c3 c4)__
AND    	 c1.user_id = ?
GROUP BY c4.tag_id
ORDER BY c4.name

__PACKAGE__->set_sql(from_user_with_like_and_limit => <<'');
SELECT 	 __ESSENTIAL(t)__
FROM   	 __TABLE(Bibliotech::User_Bookmark=ub)__,
       	 __TABLE(Bibliotech::User_Bookmark_Tag=ubt)__,
       	 __TABLE(Bibliotech::Tag=t)__
WHERE  	 __JOIN(ub ubt)__
AND    	 __JOIN(ubt t)__
AND    	 ub.user = ?
AND      t.name LIKE ?
GROUP BY t.tag_id
ORDER BY t.name
LIMIT    %s

# call search_from_bookmark() and the privacy parameter is handled for you
__PACKAGE__->set_sql(from_bookmark_need_privacy => <<'');
SELECT 	 __ESSENTIAL(t)__
FROM   	 __TABLE(Bibliotech::Bookmark=b)__,
       	 __TABLE(Bibliotech::User_Bookmark=ub)__,
       	 __TABLE(Bibliotech::User_Bookmark_Tag=ubt)__,
       	 __TABLE(Bibliotech::Tag=t)__
WHERE  	 __JOIN(b ub)__
AND    	 __JOIN(ub ubt)__
AND    	 __JOIN(ubt t)__
AND    	 b.bookmark_id = ?
AND      %s
GROUP BY t.tag_id
ORDER BY t.name

sub search_from_bookmark {
  my ($self, $bookmark_id) = @_;
  my ($privacywhere, @privacybind) = Bibliotech::Query->privacywhere($Bibliotech::Apache::USER);
  my $sth = $self->sql_from_bookmark_need_privacy($privacywhere);
  return $self->sth_to_objects($sth, [$bookmark_id, @privacybind]);
}

# call search_most_active() and the privacy parameter is handled for you
__PACKAGE__->set_sql(most_active_need_privacy => <<'');
SELECT   DISTINCT __ESSENTIAL(t)__
FROM
(
SELECT   tag, COUNT(user_bookmark) as cnt
FROM     __TABLE(Bibliotech::User_Bookmark_Tag)__
GROUP BY tag
ORDER BY cnt DESC
LIMIT    50
) as ubti
         LEFT JOIN __TABLE(Bibliotech::Tag=t)__ ON (ubti.tag = t.tag_id)
	 LEFT JOIN __TABLE(Bibliotech::User_Bookmark_Tag=ubt)__ ON (__JOIN(t ubt)__)
	 LEFT JOIN __TABLE(Bibliotech::User_Bookmark=ub)__ ON (__JOIN(ubt ub)__)
WHERE    %s
LIMIT    25

sub search_most_active {
  my ($self, $visitor) = @_;
  my $user = $visitor ? undef : $Bibliotech::Apache::USER;
  my ($privacywhere, @privacybind) = Bibliotech::Query->privacywhere($user);
  my $sth = $self->sql_most_active_need_privacy($privacywhere);
  return $self->sth_to_objects($sth, \@privacybind);
}

# call search_most_active_in_window() and the privacy parameter is handled for you
__PACKAGE__->set_sql(most_active_in_window_need_privacy => <<'');
SELECT   __ESSENTIAL(t)__,
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
	 LEFT JOIN __TABLE(Bibliotech::User_Bookmark_Tag=ubt)__ ON (__JOIN(ubt ub)__)
         LEFT JOIN __TABLE(Bibliotech::Tag=t)__ ON (__JOIN(t ubt)__)
WHERE    ub.user_bookmark_id IS NOT NULL
GROUP BY t.tag_id
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

sub standard_annotation_text {
  my ($self, $bibliotech, $register) = @_;
  my $sitename = $bibliotech->sitename;
  my $tagname = $self->name;
  return "This is a list of articles and links that have been posted by Connotea 
          users using the tag \"$tagname\". An RSS feed of the latest entries is 
          available by clicking on the icon above.  To add resources to this 
          collection, $register";
}

sub user_tag_annotations {
  Bibliotech::User_Tag_Annotation->search(tag => shift);
}

sub delete {
  #warn 'delete tag';
  my $self = shift;
  $self->user_tag_annotations->delete_all;
  $self->SUPER::delete(@_);
}

1;
__END__
