# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Query class accepts a Bibliotech::Command object, runs
# the database queries necessary, and returns a list of objects.

package Bibliotech::Query;
use strict;
use base 'Class::Accessor::Fast';
use SQL::Abstract;
use Set::Array;
use Storable qw(dclone);
use List::Util qw(sum);
use List::MoreUtils qw(any);
use Data::Dumper;
use Carp qw/cluck/;
use Bibliotech::DBI;
use Bibliotech::DBI::Set;
use Bibliotech::FilterNames;
use Bibliotech::Profile;

# introduced solely for debugging because live connotea.org was having
# deadlocks and although those are normal we'd like to diagnose the
# situation and possibly mitigate them
our $QQ1;
our $QQ2;

__PACKAGE__->mk_accessors(qw/bibliotech command memcache activeuser
			     lastcount geocount
			     bad/);

sub lastcount_debug {
  my $self = shift;
  warn 'setting lastcount = '.$_[0] if @_;
  return $self->x_lastcount(@_);
}

sub new {
  my ($class, $command_param, $bibliotech) = @_;
  my $command = eval { return $command_param if defined $command_param;
		       return $bibliotech->command if defined $bibliotech;
		       return Bibliotech::Command->new;
		     };
  my $memcache = eval { return $bibliotech->memcache if defined $bibliotech;
			return;
		      };
  return $class->SUPER::new({bibliotech => $bibliotech, command => $command, memcache => $memcache});
}

sub geotagged_tag_namepart {
  Bibliotech::Parser::NamePart->new(geotagged => 'Bibliotech::Tag');
}

sub add_geotagged_tag_to_namepart_set {
  my ($output, $filter, $namepartset) = @_;
  return $namepartset unless $output eq 'geo' and $filter eq 'tag';
  my $tag_namepart = geotagged_tag_namepart();
  my $tag_id = $tag_namepart->obj_id_or_zero or return $namepartset;
  my $add_tag = sub {
    my $namepart = shift;
    if (ref $namepart eq 'ARRAY') {
      return [@{$namepart}, $tag_namepart] unless any { $_->obj_id_or_zero == $tag_id } @{$namepart};
      return $namepart;
    }
    return [$namepart, $tag_namepart] unless $namepart->obj_id_or_zero == $tag_id;
    return $namepart;
  };
  return Bibliotech::Parser::NamePartSet->new(map { $add_tag->($_) } @{$namepartset});
}

# e.g. change /tag/blah to /tag/blah+geotagged or /tag/blah1/blah2 to /tag/blah1+geotagged/blah2+geotagged
sub filter_with_universal_and {
  my ($filter_data, $addition) = @_;
  return bless [$addition], 'Bibliotech::Parser::NamePartSet' if !$filter_data or !@{$filter_data};
  foreach (@{$filter_data}) {
    $_ = [$_] unless ref $_ eq 'ARRAY';
    push @{$_}, $addition unless grep { "$addition" eq "$_" } @{$_};
  }
  return $filter_data;
}

sub set_command_filter {
  my ($self, $filter, @obj) = @_;
  $self->bad(1) unless defined $obj[0]->id;
  $self->command->$filter(Bibliotech::Parser::NamePartSet->new
			  ([map { Bibliotech::Parser::NamePart->new($_->label, $_) } @obj]));
}

sub set_user {
  my ($self, $user) = @_;
  die 'not a user object' unless UNIVERSAL::isa($user, 'Bibliotech::User');
  $self->set_command_filter(user => $user);
}

sub set_gang {
  my ($self, $gang) = @_;
  die 'not a gang object' unless UNIVERSAL::isa($gang, 'Bibliotech::Gang');
  $self->set_command_filter(gang => $gang);
}

sub set_bookmark {
  my ($self, $bookmark) = @_;
  die 'not a bookmark object' unless UNIVERSAL::isa($bookmark, 'Bibliotech::Bookmark');
  $self->set_command_filter(bookmark => $bookmark);
}

sub set_tag {
  my ($self, $tag) = @_;
  die 'not a tag object' unless UNIVERSAL::isa($tag, 'Bibliotech::Tag');
  $self->set_command_filter(tag => $tag);
}

sub set_date {
  my ($self, $date) = @_;
  die 'not a date object' unless UNIVERSAL::isa($date, 'Bibliotech::Date');
  $self->set_command_filter(date => $date);
}

# the next 3 have to get or set

sub start {
  my $self = shift;
  $self->command->start(@_);
}

sub num {
  my $self = shift;
  $self->command->num(@_);
}

sub freematch {
  my $self = shift;
  $self->command->freematch(@_);
}

# provide the correct SQL snippet and binding parameters for privacy,
# given a particular user who is the active user
sub _privacywhere {
  my $user_id      = shift or return 'ua.def_public = 1';  # rest of routine is moot if no user
  my $gang_ids_ref = shift;

  my $PUBLIC  =       '(ua.private = 0 AND ua.private_gang IS NULL)';
  my $MINE    = sub { return unless defined $user_id;
		      'ua.user = ?', $user_id };
  my $MYGANGS = sub { return unless defined $user_id;
		      my @gangs = @{$gang_ids_ref} or return;
		      'ua.private_gang IN ('.join(',', map('?', @gangs)).')', @gangs; };
  my $EXPIRED =       '(ua.private_until IS NOT NULL AND ua.private_until <= NOW())';
  my $NOTQUAR =       'ua.quarantined IS NULL';

  my @algo    = ('(', '(', $PUBLIC, ' OR ', $MYGANGS, ' OR ', $EXPIRED, ')', ' AND ', $NOTQUAR, ')', ' OR ', $MINE);

  my (@sql, @bind);
  foreach (@algo) {  # convert algo to a sql string and bind parameters
    do { push @sql, $_; }, next unless ref $_;
    my ($add_sql, @add_bind) = $_->();
    if (defined $add_sql) {
      push @sql,  $add_sql;
      push @bind, @add_bind;
    }
    else {
      pop @sql if $sql[$#sql] eq ' OR ';  # remove preceding OR if clause evals to nothing
    }
  }
  return (join('', '(', @sql, ')'), @bind);
}

sub privacywhere {
  my ($self, $user) = @_;
  return _privacywhere(defined $user ? ($user->user_id, [map { $_->gang_id } $user->gangs]) : ());
}

# fake an INTERSECT type SQL snippet for a database lacking a real INTERSECT command
sub _sql_intersect {
  my $select_field = shift or die 'no select field';
  my $inner_field  = shift or die 'no inner field';
  my $group_field  = shift or die 'no group field';
  my $count_field  = shift or die 'no count field';
  return ''    if @_ == 0;
  return $_[0] if @_ == 1;
  my $counter = 0;
  return join('',
	      'SELECT ', $select_field, ' FROM (',
	      join(' UNION ALL ', map { join('', 'SELECT ', $inner_field, ' FROM (', $_, ') AS interinner', ++$counter) } @_),
	      ') AS inter GROUP BY ', $group_field, ' HAVING COUNT(', $count_field, ') = ', scalar(@_));
}

sub _sql_union {
  join(' UNION ', @_);
}

sub _sql_select_user_article_id {
  my $need_article_id = shift;
  return 'SELECT user_article_id' unless $need_article_id;
  my $extra = shift;
  return 'SELECT article AS article_id, user_article_id'.($extra ? ', '.$extra : '');
}

sub _sql_ua_selection_user {
  my ($namepart, $need_article_id) = @_;
  _sql_select_user_article_id($need_article_id, 'user AS user_id')
      .' FROM user_article WHERE user = '.$namepart->obj_id_or_zero;
}

sub _sql_ua_selection_tag {
  my ($namepart, $need_article_id) = @_;
  return 'SELECT user_article AS user_article_id FROM user_article_tag WHERE tag = '.$namepart->obj_id_or_zero
      unless $need_article_id;
  return 'SELECT ua.article AS article_id, ua.user_article_id, uat.tag AS tag_id FROM user_article_tag uat LEFT JOIN user_article ua ON (uat.user_article = ua.user_article_id) WHERE uat.tag = '.$namepart->obj_id_or_zero;
}

sub _sql_ua_selection_gang {
  my ($namepart, $need_article_id) = @_;
  _sql_select_user_article_id($need_article_id, 'ug.gang AS gang_id')
      .' FROM user_gang ug LEFT JOIN user_article ua ON (ug.user = ua.user) WHERE ug.gang = '.$namepart->obj_id_or_zero;
}

sub _sql_ua_selection_date {
  my ($namepart, $need_article_id) = @_;
  my $date = $namepart->obj->mysql_date;
  _sql_select_user_article_id($need_article_id, 'TO_DAYS(created) AS date_id')
      ." FROM user_article WHERE created BETWEEN \'$date 00:00:00\' AND \'$date 23:59:59\'";
}

sub _sql_ua_selection_bookmark {
  my ($namepart, $need_article_id) = @_;
  _sql_select_user_article_id($need_article_id)
      .' FROM bookmark b LEFT JOIN article a ON (b.article = a.article_id) LEFT JOIN user_article ua ON (a.article_id = ua.article) WHERE bookmark_id = '.$namepart->obj_id_or_zero;
}

sub _sql_ua_selection_article {
  my ($namepart, $need_article_id) = @_;
  _sql_select_user_article_id($need_article_id)
      .' FROM article a LEFT JOIN user_article ua ON (a.article_id = ua.article) WHERE a.article_id = '.$namepart->obj_id_or_zero;
}

sub _sql_user_tag_super_optimized {
  my ($user_namepart, $tag_namepart) = @_;
  my $user_id = $user_namepart->obj_id_or_zero;
  my $tag_id  = $tag_namepart->obj_id_or_zero;
  return "SELECT ua.user_article_id FROM user_article ua LEFT JOIN user_article_tag uat ON (ua.user_article_id = uat.user_article) WHERE ua.user = $user_id AND uat.tag = $tag_id";
}

sub _sql_user_date_super_optimized {
  my ($user_namepart, $date_namepart) = @_;
  my $user_id = $user_namepart->obj_id_or_zero;
  my $date    = $date_namepart->obj->mysql_date;
  return "SELECT user_article_id FROM user_article WHERE user = $user_id AND created BETWEEN \'$date 00:00:00\' AND \'$date 23:59:59\'";
}

sub _sql_user_article_super_optimized {
  my ($user_namepart, $article_namepart) = @_;
  my $user_id    = $user_namepart->obj_id_or_zero;
  my $article_id = $article_namepart->obj_id_or_zero;
  return "SELECT user_article_id FROM user_article WHERE user = $user_id AND article = $article_id";
}

sub _sql_user_bookmark_super_optimized {
  my ($user_namepart, $bookmark_namepart) = @_;
  my $user_id     = $user_namepart->obj_id_or_zero;
  my $bookmark_id = $bookmark_namepart->obj_id_or_zero;
  return "SELECT user_article_id FROM user_article WHERE user = $user_id AND bookmark = $bookmark_id";
}

sub _sql_user_gang_super_optimized {
  my ($user_namepart, $gang_namepart) = @_;
  my $user_id = $user_namepart->obj_id_or_zero;
  my $gang_id = $gang_namepart->obj_id_or_zero;
  return "SELECT ua.user_article_id FROM user_gang ug INNER JOIN user_article ua ON (ug.user = ua.user) WHERE ug.user = $user_id AND ug.gang = $gang_id";
}

sub _sql_tag_date_super_optimized {
  my ($tag_namepart, $date_namepart) = @_;
  my $tag_id = $tag_namepart->obj_id_or_zero;
  my $date   = $date_namepart->obj->mysql_date;
  return "SELECT ua.user_article_id FROM user_article ua LEFT JOIN user_article_tag uat ON (ua.user_article_id = uat.user_article) WHERE uat.tag = $tag_id AND ua.created BETWEEN \'$date 00:00:00\' AND \'$date 23:59:59\'";
}

sub _sql_tag_article_super_optimized {
  my ($tag_namepart, $article_namepart) = @_;
  my $tag_id     = $tag_namepart->obj_id_or_zero;
  my $article_id = $article_namepart->obj_id_or_zero;
  return "SELECT DISTINCT ua.user_article_id FROM user_article_tag uat LEFT JOIN user_article ua ON (ua.user_article_id = uat.user_article) WHERE uat.tag = $tag_id AND ua.article = $article_id";
}

sub _sql_tag_bookmark_super_optimized {
  my ($tag_namepart, $bookmark_namepart) = @_;
  my $tag_id      = $tag_namepart->obj_id_or_zero;
  my $bookmark_id = $bookmark_namepart->obj_id_or_zero;
  return "SELECT DISTINCT ua.user_article_id FROM user_article_tag uat LEFT JOIN user_article ua ON (ua.user_article_id = uat.user_article) LEFT JOIN bookmark b ON (b.article = ua.article) WHERE uat.tag = $tag_id AND b.bookmark_id = $bookmark_id";
}

sub _sql_gang_tag_super_optimized {
  my ($gang_namepart, $tag_namepart) = @_;
  my $gang_id = $gang_namepart->obj_id_or_zero;
  my $tag_id  = $tag_namepart->obj_id_or_zero;
  return "SELECT ua.user_article_id FROM user_gang ug INNER JOIN user_article ua ON (ug.user = ua.user) LEFT JOIN user_article_tag uat ON (ua.user_article_id = uat.user_article) WHERE ug.gang = $gang_id AND uat.tag = $tag_id";
}

sub _sql_gang_date_super_optimized {
  my ($gang_namepart, $date_namepart) = @_;
  my $gang_id = $gang_namepart->obj_id_or_zero;
  my $date    = $date_namepart->obj->mysql_date;
  return "SELECT ua.user_article_id FROM user_gang ug INNER JOIN user_article ua ON (ug.user = ua.user) WHERE ug.gang = $gang_id AND ua.created BETWEEN \'$date 00:00:00\' AND \'$date 23:59:59\'";
}

sub _sql_date_article_super_optimized {
  my ($date_namepart, $article_namepart) = @_;
  my $date       = $date_namepart->obj->mysql_date;
  my $article_id = $article_namepart->obj_id_or_zero;
  return "SELECT user_article_id FROM user_article WHERE article = $article_id AND created BETWEEN \'$date 00:00:00\' AND \'$date 23:59:59\'";
}

sub _sql_gang_article_super_optimized {
  my ($gang_namepart, $article_namepart) = @_;
  my $gang_id     = $gang_namepart->obj_id_or_zero;
  my $article_id = $article_namepart->obj_id_or_zero;
  return "SELECT ua.user_article_id FROM user_gang ug INNER JOIN user_article ua ON (ug.user = ua.user) WHERE ug.gang = $gang_id AND ua.article = $article_id";
}

sub _sql_super_optimized {
  my ($earlier_filter, $earlier_namepart, $later_filter, $later_namepart) = @_;
  no strict 'refs';
  return &{'_sql_'.$earlier_filter.'_'.$later_filter.'_super_optimized'}($earlier_namepart, $later_namepart);
}

sub _sql_ua_selection {
  my ($namepart, $need_article_id) = @_;

  defined $namepart or die 'no namepart';
  UNIVERSAL::isa($namepart, 'Bibliotech::Parser::NamePart') or die 'namepart is wrong type: '.ref($namepart);
  defined $need_article_id or die 'no need_article_id flag';

  my $class = $namepart->class;
  return _sql_ua_selection_user($namepart, $need_article_id)     if $class eq 'Bibliotech::User';
  return _sql_ua_selection_user($namepart, $need_article_id)     if $class eq 'Bibliotech::User';
  return _sql_ua_selection_tag($namepart, $need_article_id)      if $class eq 'Bibliotech::Tag';
  return _sql_ua_selection_gang($namepart, $need_article_id)     if $class eq 'Bibliotech::Gang';
  return _sql_ua_selection_date($namepart, $need_article_id)     if $class eq 'Bibliotech::Date';
  return _sql_ua_selection_bookmark($namepart, $need_article_id) if $class eq 'Bibliotech::Bookmark';
  return _sql_ua_selection_article($namepart, $need_article_id)  if $class eq 'Bibliotech::Article';
  die "_sql_ua_selection unhandled class ($class)";
}

sub _sql_get_user_article_ids_for_one_criterion {
  my $namepart = shift;
  _sql_ua_selection($namepart, 0);
}

sub _sql_get_user_article_ids_and_article_ids_for_one_criterion {
  my $namepart = shift;
  _sql_ua_selection($namepart, 1);
}

sub _sql_get_all_user_article_ids {
  'SELECT user_article_id FROM user_article';
}

sub _search_ua_optimized_sql_select_user_article_ids_only {
  my ($output, $get_namepartset, $filters_used, $is_two_filters_used_once) = @_;
      
  return _sql_super_optimized(map { $_ => @{$get_namepartset->($_)} } $filters_used->()) if $is_two_filters_used_once->();

  my $OR_ua  = sub { _sql_union    (@_) };
  my $AND_ua = sub { _sql_intersect(('user_article_id') x 4, @_) };
  my $AND_b  = sub { my $filter = shift;
		     my $needs_merge_on_article_id = $filter =~ /^(?:user|gang|date)$/ && @_ > 1;
		     return $AND_ua->(map { $_->(0) } @_) unless $needs_merge_on_article_id;
                     _sql_intersect('MAX(user_article_id) AS user_article_id',
				    "article_id, user_article_id, ${filter}_id",
				    'article_id',
				    "DISTINCT ${filter}_id",
				    map { $_->(1) } @_) };
  my $ALL    = sub { local $_ = shift; ref $_ eq 'ARRAY' ? @{$_} : ($_) };
  my $nameparts_specified = sub { local $_ = shift;
				  @{add_geotagged_tag_to_namepart_set($output, $_, $get_namepartset->($_) || [])} };

  return $AND_ua->(map { my $filter = $_;      # AND the filters: /user/martin/tag/perl = martin AND perl
           $OR_ua->(map { my $slashpart = $_;  # OR the parts of a filter: /user/martin/ben = martin OR ben
     	     $AND_b->($filter,                 # AND the plus'd parts: /user/martin+ben = martin AND ben
     		      map { my $namepart = $_;
			    sub { $_[0]
				  ? _sql_get_user_article_ids_and_article_ids_for_one_criterion($namepart)
				  : _sql_get_user_article_ids_for_one_criterion($namepart)
				};
     	     } $ALL->($slashpart))
     	   } $nameparts_specified->($filter))
         } $filters_used->())
         || _sql_get_all_user_article_ids();
}

sub _search_ua_optimized_sql_select_user_article_ids_only_using_command {
  my $command = shift;
  return _search_ua_optimized_sql_select_user_article_ids_only
      ($command->output,
       sub { my $filter = shift; $command->$filter },
       sub { $command->filters_used },
       sub { (my @filters_used = $command->filters_used) == 2  or return;
	     $command->filters_used_only_single(@filters_used) or return;
	     return 1; },
      );
}

sub _search_ua_optimized_count {
  my ($sql_select_user_article_ids_only_with_privacy, $privacybind_ref) = @_;

  my $sth = Bibliotech::User_Article->psql_packed_count_query_using_subselect
      ($sql_select_user_article_ids_only_with_privacy);
  Bibliotech::Profile::start('query object waiting for mysql for count (_search_ua_optimized)');
  eval { $sth->execute(@{$privacybind_ref}) or die $sth->errstr };
  die "count execute died: $@" if $@;
  my ($count) = $sth->fetchrow_array;
  $sth->finish;
  Bibliotech::Profile::stop();

  return $count;
}

sub _search_ua_optimized_data {
  my ($sql_select_user_article_ids_only_with_privacy, $privacywhere, $privacybind_ref, $activeuser, $sort, $sortdir, $start, $num) = @_;

  my @select       = Bibliotech::User_Article->packed_select;
  my $limit        = join(' ', 'LIMIT', int($start).',', int($num) || 100000);
  my $orderby      = join(' ', 'ORDER BY', $sort || 'ua.created', $sortdir || 'DESC');
  my @privacybind  = @{$privacybind_ref};
  (my $uao_orderby = $orderby) =~ s/\bua\./uao./g;
  Bibliotech::Profile::start('_search_ua_optimized_data creating temp table qq2');
  my $qq2 = join(' ', $sql_select_user_article_ids_only_with_privacy, $uao_orderby, $limit);
  my $dbh = Bibliotech::DBI->db_Main;
  eval {
    eval { $dbh->do('DROP TEMPORARY TABLE IF EXISTS qq2'); };  # for buggy situations
    die 'dropping temporary table qq2: '.$@ if $@;
    eval { $dbh->do($QQ2 = 'CREATE TEMPORARY TABLE qq2 AS '.$qq2, undef, @privacybind) or die 'failed qq2 creation'; };
    die 'creating temporary table qq2: '.$@ if $@;
    eval { $dbh->do('ALTER TABLE qq2 ADD INDEX user_article_id_idx (user_article_id)') or die 'failed qq2 indexing'; };
    die 'adding index to qq2: '.$@ if $@;
  };
  die "setting up qq2: $@" if $@;
  Bibliotech::Profile::stop();

  my $sth = Bibliotech::User_Article->psql_packed_query_using_subselect
      (join(', ', @select),
       'qq2',
       $privacywhere,
       $orderby);

  Bibliotech::Profile::start('query object waiting for mysql for data (_search_ua_optimized)');
  my $activeuser_id = eval { return 0 unless defined $activeuser;
			     return $activeuser unless ref $activeuser;
			     return $activeuser->user_id;
			   };
  eval { $sth->execute(@privacybind, $activeuser_id) or die $sth->errstr };
  die "data execute died: $@" if $@;
  my @data = @{$sth->fetchall_arrayref};
  Bibliotech::Profile::stop();

  Bibliotech::Profile::start('converting packed arrays to user_article objects');
  my $names_ref = Bibliotech::User_Article->select2names(\@select);
  my $set = Bibliotech::DBI::Set->new(map { Bibliotech::User_Article->unpack_packed_select($names_ref, $_) }
				      map { bless($_, 'Bibliotech::DBI::Set::Line') }
				      @data);
  Bibliotech::Profile::stop();

  return ($set,
	  sum map { $_->is_geotagged || 0 } @{$set});  # geocount
}

sub _search_ua_optimized_sql_select_user_article_ids_only_with_privacy {
  my ($sql_select_user_article_ids_only, $privacywhere) = @_;
  (my $uao_privacywhere = $privacywhere) =~ s/\bua\./uao./g;
  return "SELECT uas.user_article_id FROM ($sql_select_user_article_ids_only) AS uas ".
         "NATURAL JOIN user_article uao WHERE $uao_privacywhere AND uao.user_article_id IS NOT NULL";
}

sub _search_ua_optimized_sql_select_user_article_ids_only_with_privacy_qq {
  my ($sql_select_user_article_ids_only, $privacywhere) = @_;
  if ($sql_select_user_article_ids_only eq 'SELECT user_article_id FROM user_article') {
    (my $uao_privacywhere = $privacywhere) =~ s/\bua\./uao./g;
    return "SELECT uao.user_article_id FROM user_article AS uao WHERE $uao_privacywhere";
  }
  else {
    my $dbh = Bibliotech::DBI->db_Main;
    eval {
      eval { $dbh->do('DROP TEMPORARY TABLE IF EXISTS qq1'); };  # for buggy situations
      die 'dropping temporary table qq1: '.$@ if $@;
      eval { $dbh->do($QQ1 = 'CREATE TEMPORARY TABLE qq1 AS '.$sql_select_user_article_ids_only) or die 'failed qq1 creation'; };
      die 'creating temporary table qq1: '.$@ if $@;
      eval { $dbh->do('ALTER TABLE qq1 ADD INDEX user_article_id_idx (user_article_id)') or die 'failed qq1 indexing'; };
      die 'adding index to qq1: '.$@ if $@;
    };
    die "setting up qq1: $@" if $@;
  }
  (my $uao_privacywhere = $privacywhere) =~ s/\bua\./uao./g;
  return "SELECT uas.user_article_id FROM qq1 AS uas ".
         "NATURAL JOIN user_article uao WHERE $uao_privacywhere AND uao.user_article_id IS NOT NULL";
}

# _search_ua_optimized does the same as _search() provided that there
# are no options to _search() in excess of the parameters that
# _search_ua_optimized() accepts, except class which must be
# 'Bibliotech::User_Article'.
sub _search_ua_optimized {
  my ($self, $activeuser, $sort, $sortdir, $start, $num) = @_;

  Bibliotech::Profile::start(sub { join(' ',
					'_search_ua_optimized:',
					$activeuser,
					$sort, $sortdir,
					$start, $num,
					$self->command->description,
				       )});

  $QQ1 = '';
  $QQ2 = '';

  my ($set, $geocount, $count);

  my $dbh = Bibliotech::DBI::db_Main;
  $dbh->do('SET AUTOCOMMIT=0');
  eval {

    Bibliotech::Profile::start('_search_ua_optimized creating temp table qq1');

    my ($privacywhere, @privacybind) = $self->privacywhere($activeuser);
    my $sql_select_user_article_ids_only_with_privacy =
	_search_ua_optimized_sql_select_user_article_ids_only_with_privacy_qq
	(_search_ua_optimized_sql_select_user_article_ids_only_using_command($self->command),
	 $privacywhere);

    Bibliotech::Profile::stop();

    ($set, $geocount) = _search_ua_optimized_data ($sql_select_user_article_ids_only_with_privacy,
						   $privacywhere, \@privacybind,
						   $activeuser, $sort, $sortdir, $start, $num);
    $count            = _search_ua_optimized_count($sql_select_user_article_ids_only_with_privacy,
						   \@privacybind);
  };
  my $e = $@;

  $dbh->do('DROP TEMPORARY TABLE IF EXISTS qq1');
  $dbh->do('DROP TEMPORARY TABLE IF EXISTS qq2');

  if ($e) {
    $dbh->do('ROLLBACK');
    $dbh->do('SET AUTOCOMMIT=1');
    die "$e\nQQ1:\n$QQ1\nQQ2:\n$QQ2\n";
  }
  $dbh->do('COMMIT');
  $dbh->do('SET AUTOCOMMIT=1');

  Bibliotech::Profile::stop();

  return ($set, $count, $geocount);
}

sub _full_count {
  my ($self, $name, $activeuser, $sql_wrap, $params_ref) = @_;
  my ($privacywhere, @privacybind) = $self->privacywhere($activeuser);
  my $subselect = _search_ua_optimized_sql_select_user_article_ids_only_with_privacy(_search_ua_optimized_sql_select_user_article_ids_only_using_command($self->command), $privacywhere);
  my $sth = Bibliotech::DBI->db_Main->prepare_cached(sprintf($sql_wrap, $subselect));
  Bibliotech::Profile::start('query object waiting for mysql for '.$name);
  eval { $sth->execute(@privacybind, @{$params_ref||[]}) or die $sth->errstr };
  die "$name execute died: $@" if $@;
  my ($count) = $sth->fetchrow_array;
  $sth->finish;
  Bibliotech::Profile::stop();
  return $count;
}

sub full_count {
  my ($self, $activeuser) = @_;
  my $sql = "SELECT COUNT(uajg.user_article_id) FROM (%s) AS uajg";
  return $self->_full_count('count', $activeuser, $sql);
}

sub full_geocount {
  my ($self, $activeuser) = @_;
  my $tag_id = geotagged_tag_namepart()->obj_id_or_zero or return 0;
  my $sql = "SELECT COUNT(uajg.user_article_id) FROM (%s) AS uajg LEFT JOIN user_article_tag uat ON (uajg.user_article_id = uat.user_article) WHERE uat.tag = ?";
  return $self->_full_count('geocount', $activeuser, $sql, [$tag_id]);
}

sub _search {
  my ($self, %options) = @_;

  #cluck join(' ', '_search:', (map { $_.'='.$options{$_} } sort keys %options))."\n";

  return Bibliotech::DBI::Set->new if $self->bad;

  my $class = $options{class};
  my $primary = $class->primary_column;
  my $cache_key;
  my $last_updated;
  my ($final_set, $sortvalue_ref);
  delete $options{main};  # passed in sometimes, but not used

  my $memcache = $self->memcache;
  if (defined $memcache) {
    $cache_key = Bibliotech::Cache::Key->new($self->bibliotech,
					     class => __PACKAGE__,
					     method => '_search',
					     user => undef,
					     path => undef,
					     options => \%options);
    $last_updated = Bibliotech::DBI->db_get_last_updated;
    my $data = $memcache->get_with_last_updated($cache_key, $last_updated, undef, 1);
    $final_set = $data->[0];
    $self->lastcount($data->[1]);
    $self->geocount($data->[2]);
  }

  unless (defined $final_set) {
    unless ($options{class} ne 'Bibliotech::User_Article' or
	    $options{freematch} or
	    $self->freematch or
	    $options{no_freematch} or
	    $options{all} or
	    $options{forcegroup} or
	    $options{where} or
	    $options{having}) {
      my ($optimized_count, $optimized_geocount);
      ($final_set, $optimized_count, $optimized_geocount) = 
	  $self->_search_ua_optimized($options{activeuser} || $self->activeuser,
				      $options{sort},
				      $options{sortdir},
				      $options{start} || $self->start,
				      $options{num} || $self->num);
      $self->lastcount($optimized_count);
      $self->geocount($optimized_geocount);
      $memcache->set_with_last_updated($cache_key, [$final_set, $optimized_count, $optimized_geocount], $last_updated)
	  if $memcache;
    }
  }

  unless (defined $final_set) {
    my $sort = $options{sort};
    my $sortdir = $options{sortdir};
    my $sortnumeric = $options{sortnumeric};
    my $all = $options{all};
    my $noquery = $options{noquery};
    my $forcegroup = $options{forcegroup};
    my @extrawhere;
    @extrawhere = @{$options{where}} if $options{where};
    my @extrahaving;
    @extrahaving = @{$options{having}} if $options{having};
    my $activeuser = $options{activeuser} || $self->activeuser;

    my ($privacywhere, @privacybind) = $self->privacywhere($activeuser);
    
    # for each of various keys (USER ARTICLE TAG DATE) there can zero or more search matches
    # the matches are OR'd
    # if a match is an arrayref the constituent elements are AND'd
    # psuedo-code:
    # loop over the keys
    #   loop over the matches
    #     perform a SQL query (nested AND's handled here)
    #   union (OR) the results of the matches
    # intersect (AND) the results of the three keys
    # provide final results back as a raw array of primary keys or in a Class::DBI-friendly way

    my $alias = join('', map(substr($_, 0, 1), split(/_/, $class->table)));
    my $alias_primary = "$alias.$primary";
    my $alias_created = "LEFT($alias.created,10)";
    my @select;
    if ($class->can('packed_select')) {
      @select = $class->packed_select;
      @select = grep(!/geotagged/, @select) if $self->command->filters_used;
    }
    else {
      @select = map("$alias.$_", $class->_essential);
    }
    my @names;
    my $group;
    if ($forcegroup) {
      $group = $forcegroup;
    }
    else {
      $group = $alias_primary;
      if ($group eq 'ua.user_article_id' and !$self->command->filters_used) {
	foreach (@select) {
	  s/^$alias_primary$/MAX($alias_primary)/;
	}
	$group = 'b.article';
      }
    }
    my $groupby = $group ? "GROUP BY $group" : '';
    if (!$sort) {
      $sort = "UNIX_TIMESTAMP($alias.created)";
      $sort = "MAX($sort)" if $select[0] =~ /MAX/;
    }
    my $freematch = $options{freematch};
    $freematch = $self->freematch if !$all and !$noquery and !$freematch and !$options{no_freematch};
    my @freematch = $freematch ? @{$freematch->terms} : ();
    push @select, "$sort AS sortvalue" if $sort;
    $sortdir ||= 'DESC';
    my $orderby = "ORDER BY sortvalue $sortdir";
    my $start = $options{start};
    $start = $self->start || 0 if !$all and !$noquery and !$start;
    my $num = $options{num};
    $num = $self->num if !$all and !$noquery and !$num;

    my $sql_query_count = 0;
    my $sql_query_expected_count = 0;
    my $use_limit_shortcut = 1;
    my $limit_shortcut_count;
    foreach (@FILTERS) {
      my $key = $_->{name};
      my $value = $self->command->$key;
      next unless $value && @{$value};
      $sql_query_expected_count++;
      $use_limit_shortcut = 0 if @{$value} != 1 or ref($value->[0]) eq 'ARRAY';
    }
    $sql_query_expected_count ||= 1;
    $use_limit_shortcut = 0 if $sql_query_expected_count > 1 or !$num;

    my $geotagged_count;

    foreach (@FILTERS, {code => 'DUMMY'}) {
      my ($key, $fname, $id_table, $id, $textcolumn)
	  = ($_->{code}, $_->{name}, $_->{table}, $_->{table_primary}, $_->{table_search});

      if ($key eq 'DUMMY') {
	next if defined $final_set;
      }
      elsif ($key eq 'DATE') {
	$id = $alias_created;
	$textcolumn = "$alias.created";
      }
      else {
	next if $noquery;
      }

      my $value = eval { return [1] if $key eq 'DUMMY';
			 return add_geotagged_tag_to_namepart_set($self->command->output,
								  $fname,
								  $self->command->$fname); };
      next unless $value && @{$value};

      my $key_set;
      foreach my $match_raw (@{$value}) {

	my $reduce_namepart_to_text = sub {
	  my $namepart = shift;
	  return $namepart unless ref $namepart;
	  my $obj = $namepart->obj;
	  return 'INVALID' unless defined $obj;
	  my $primary = $obj->primary_column;
	  return $obj->$primary if $primary;
	  return $obj->query_format if $obj->can('query_format');
	  return "$obj";
	};

	my $match = eval { return $reduce_namepart_to_text->($match_raw) unless ref $match_raw eq 'ARRAY';
			   return [map { $reduce_namepart_to_text->($_) } @{$match_raw}]; };
	die $@ if $@;

	my $checkcount = ref $match ? @{$match} : undef;
	my $or_item_set = new Bibliotech::DBI::Set;
	if ((ref($match) eq 'ARRAY' and grep($_ eq 'INVALID', @{$match})) or $match eq 'INVALID') {
	  # noop
	}
	else {
	  my @thisselect = @select;
	  my $thisgroupby = $groupby;
	  if ($alias eq 'ua' and (ref $match or $key eq 'DUMMY')) {
	    @thisselect[0] = "MAX($alias_primary)";
	    $thisgroupby = 'GROUP BY b.article';
	  }

	  my $sql = new SQL::Abstract;
	  my %criteria = @{dclone(\@extrawhere)};
	  if ($key ne 'DUMMY') {
	    my @match = (ref $match ? @{$match} : $match);
	    foreach (@match) {
	      if (/^~(~?)(.+)$/) {
		$criteria{$textcolumn} ||= [];
		push @{$criteria{$textcolumn}}, $1 ? {RLIKE => $2} : {LIKE => "\%$2\%"};
	      }
	      else {
		$criteria{$id} ||= [];
		push @{$criteria{$id}}, $_;
	      }
	    }
	  }
	  my ($where, @wbind) = $sql->where(\%criteria);
	  $where =~ s/\s*WHERE\s*//i;
	  my $main_where = $where;
	  $main_where = "($main_where) AND " if $main_where;
	  $main_where .= "$alias_primary IS NOT NULL";
	  my ($having, @hbind) = $sql->where({$checkcount ? ("COUNT(DISTINCT $id)" => $checkcount) : (), @extrahaving});
	  $having =~ s/\s*WHERE\s*/HAVING /i;
	  my ($sql, $sth, %sql_options, @sql_execute);
	  $sql_query_count++;
	  eval {
	    my $thisselect = join(', ', @thisselect);
	    %sql_options = (class => $class,
			    select => \@thisselect,
			    where => $main_where,
			    group_by => $thisgroupby,
			    having => $having,
			    order_by => $orderby,
			    freematch => \@freematch);
	    if ($use_limit_shortcut) {
	      die "start option \"$start\" is not numeric" unless $start =~ /^\d+$/;
	      die "num option \"$num\" is not numeric"     unless $num   =~ /^\d+$/;
	      $sql_options{limit} = "LIMIT $start, $num";
	    }
	    if ($thisselect =~ /\b(ua|u|a|b|t|g)\./) {
	      $sql_options{join_ua} = $privacywhere;
	      $sql_options{bind_ua} = \@privacybind;
	    }
	    if ($thisselect =~ /\bua2\./) {
	      (my $ua2_privacywhere = $privacywhere) =~ s/ua\./ua2\./g;
	      $sql_options{join_ua2} = $ua2_privacywhere;
	      $sql_options{bind_ua2} = \@privacybind;
	    }
	    if ($thisselect =~ /\bua3\./) {
	      $sql_options{join_ua3} = 'ua3.user = ?';
	      $sql_options{bind_ua3} = [$activeuser ? $activeuser->user_id : 0];
	    }
	    if ($thisselect =~ /\bt4\./) {
	      $sql_options{join_t4} = 't4.name = ?';
	      $sql_options{bind_t4} = ['geotagged'];
	    }
	    $sql_options{wbind} = \@wbind;
	    $sql_options{hbind} = \@hbind;
	    my $sql_bind;
	    ($sql, $sql_bind) = Bibliotech::DBI->sql_joined_dynamic(%sql_options);
	    @sql_execute = @{$sql_bind} if $sql_bind;
	    Bibliotech::DBI::debug_warn_sql($sql);
	    $sth = Bibliotech::DBI->db_Main->prepare_cached($sql);
	    Bibliotech::Profile::start('query object waiting for mysql for data');
	    warn Dumper(\@sql_execute) if $Bibliotech::DBI::DEBUG_WARN_SQL;
	    $sth->execute(@sql_execute) or die $sth->errstr;
	    Bibliotech::Profile::stop();
	  };
	  if ($@) {
	    if ($@ =~ /all negative terms/) {
	      $or_item_set = Bibliotech::DBI::Set->new;
	    }
	    else {
	      die $@;
	    }
	  }
	  else {
	    $or_item_set = Bibliotech::DBI::Set->new
		            (map { bless $_, 'Bibliotech::DBI::Set::Line'; } @{$sth->fetchall_arrayref});
	  }

	  if ($use_limit_shortcut) {
	    eval {
	      my $distinct = 'ua.user_article_id';
	      if ($thisgroupby =~ /^GROUP BY ua\.(\w+)/ or
		  $thisgroupby =~ /^GROUP BY a\.(article)_id/ or
		  $thisgroupby =~ /^GROUP BY b\.(bookmark)_id/ or
		  $thisgroupby =~ /^GROUP BY u\.(user)_id/) {
		$distinct = 'ua.'.$1;
	      }
	      my $count_sql;
	      my @count_bind;
	      my $special_additions = @freematch || $options{where} || $options{having};
	      if (!$self->command->filters_used and !$special_additions) {
		$count_sql = "SELECT COUNT(DISTINCT $distinct) FROM user_article ua WHERE $privacywhere";
		@count_bind = @privacybind;
	      }
	      elsif ($key eq 'ARTICLE' and !$special_additions) {
		$count_sql = "SELECT COUNT(DISTINCT $distinct) FROM user_article ua LEFT JOIN article a ON (ua.article=a.article_id) WHERE $where AND $privacywhere";
		@count_bind = (@wbind, @privacybind);
	      }
	      else {
		%sql_options = (count => 1,
				class => $class,
				select => ["COUNT(DISTINCT $distinct)"],
				join_ua => $privacywhere,
				bind_ua => \@privacybind,
				where => $where,
				wbind => \@wbind,
				freematch => \@freematch);
		my $count_bind;
		($count_sql, $count_bind) = Bibliotech::DBI->sql_joined_dynamic(%sql_options);
		@count_bind = @{$count_bind} if $count_bind;
	      }
	      Bibliotech::DBI::debug_warn_sql($count_sql);
	      $sth = Bibliotech::DBI->db_Main->prepare_cached($count_sql);
	      Bibliotech::Profile::start('query object waiting for mysql for count');
	      $sth->execute(@count_bind) or die $sth->errstr;
	      Bibliotech::Profile::stop();
	      ($limit_shortcut_count) = $sth->fetch;
	      $sth->finish;
	    };
	    if ($@) {
	      if ($@ =~ /all negative terms/) {
		$limit_shortcut_count = 0;
	      }
	      else {
		die $@;
	      }
	    }
	  }
	}
	if (defined $key_set) { $key_set->union($or_item_set); } else { $key_set = $or_item_set; }
      }
      if (defined $final_set) { $final_set->intersection($key_set); } else { $final_set = $key_set; }
    }

    if ($sql_query_count > 1) {  # a resort maybe in order if sets were joined in perl
      my $sortpos = $#select;
      if ($sortnumeric) {
	$final_set->sort($sortdir eq 'DESC'
			 ? sub { $b->[$sortpos] <=> $a->[$sortpos] }
			 : sub { $a->[$sortpos] <=> $b->[$sortpos] });
      }
      else {
	$final_set->sort($sortdir eq 'DESC'
			 ? sub { lc($b->[$sortpos]) cmp lc($a->[$sortpos]) }
			 : sub { lc($a->[$sortpos]) cmp lc($b->[$sortpos]) });
      }
    }

    if (defined $limit_shortcut_count) {
      $self->lastcount($limit_shortcut_count);  # save pre-limit count of matches
    }
    else {
      my $length = $final_set->length;
      $self->lastcount($length);  # save pre-limit count of matches
    }

    my $gpos;
    for (my $i = $#select; $i >= 0; $i--) {
      if ($select[$i] =~ /ua_is_geotagged/) {
	$gpos = $i;
	last;
      }
    }
    if (defined $gpos) {
      $geotagged_count = 0;
      foreach (@{$final_set}) {
	$geotagged_count += $_->[$gpos];
      }
      $self->geocount($geotagged_count);
    }

    if (!$use_limit_shortcut) {
      splice @$final_set, 0, $start if $start;  # the class method doesn't work with Set::Array 0.11, it doubles the length!
      splice @$final_set, $num if defined $num and @$final_set > $num;
    }

    if ($class->can('unpack_packed_select')) {
      foreach (@$final_set) {
	$_ = $class->unpack_packed_select(\@select, $_);
      }
    }
    else {
      foreach (@select) {
	if (/ AS (.*)$/i) {
	  push @names, $1;
	}
	else {
	  my $field = $_;
	  $field =~ s/^MAX\((.*)\)$/$1/;
	  $field =~ s/^\w+\.//;
	  push @names, $field;
	}
      }
      foreach (@$final_set) {
	my @data = @$_;
	my %data;
	foreach (@names) {
	  $data{$_} = shift @data;
	}
	$_ = $class->construct(\%data);
      }
    }

    $memcache->set_with_last_updated($cache_key, [$final_set, $self->lastcount, $self->geocount], $last_updated) if $memcache;
  }

  return wantarray ? @{$final_set} : $final_set;
}

sub users         { shift->_search(class => 'Bibliotech::User', @_); }
sub tags          { shift->_search(class => 'Bibliotech::Tag', @_); }
sub gangs         { shift->_search(class => 'Bibliotech::Gang', @_); }
sub bookmarks     { shift->_search(class => 'Bibliotech::Bookmark', @_); }
sub articles      { shift->_search(class => 'Bibliotech::Article', @_); }
sub user_articles { shift->_search(class => 'Bibliotech::User_Article', @_); }
sub recent        { shift->user_articles(@_); }
sub popular       { shift->user_articles(sort => 'COUNT(DISTINCT ua.user)', @_); }
sub home          { shift->user_articles(@_); }

1;
__END__
