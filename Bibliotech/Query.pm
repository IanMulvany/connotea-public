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
  my ($user_id, $gang_ids_ref) = @_;

  # short-circuit if we can use def_public index for a visitor
  # the private_until check is undesirable, we have to have it because it changes with time
  defined $user_id or return '(ub.def_public = 1 OR ub.private_until <= NOW())';

  my $PUBLIC  =       '(ub.private = 0 AND ub.private_gang IS NULL)';
  my $MINE    = sub { return unless defined $user_id;
		      'ub.user = ?', $user_id };
  my $MYGANGS = sub { return unless defined $user_id;
		      my @gangs = @{$gang_ids_ref} or return;
		      'ub.private_gang IN ('.join(',', map('?', @gangs)).')', @gangs; };
  my $EXPIRED =       '(ub.private_until IS NOT NULL AND ub.private_until <= NOW())';
  my $NOTQUAR =       'ub.quarantined IS NULL';

  #my @algo   = ($PUBLIC, 'OR', $MINE, 'OR', $MYGANGS, 'OR', $EXPIRED);
  my @algo    = ('(', '(', $PUBLIC, ' OR ', $MYGANGS, ' OR ', $EXPIRED, ')', ' AND ', $NOTQUAR, ')', ' OR ', $MINE);

  # convert algo to a sql string and bind parameters
  my (@sql, @bind);
  foreach (@algo) {
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

sub _sql_intersect {
  my $select_field = shift or die 'no select field';
  my $inner_field  = shift or die 'no inner field';
  my $group_field  = shift or die 'no group field';
  my $count_field  = shift or die 'no count field';
  return ''    if @_ == 0;
  return $_[0] if @_ == 1;
  my $counter = 0;
  return "SELECT $select_field FROM ("
         .join(' UNION ALL ', map { "SELECT $inner_field FROM ($_) AS interinner".(++$counter) } @_)
         .") AS inter GROUP BY $group_field HAVING COUNT($count_field) = ".scalar(@_);
}

sub _sql_union {
  join(' UNION ', @_);
}

sub _sql_select_user_bookmark_id {
  my $need_bookmark_id = shift;
  return 'SELECT user_bookmark_id' unless $need_bookmark_id;
  my $extra = shift;
  return 'SELECT bookmark AS bookmark_id, user_bookmark_id, '.$extra;
}

sub _sql_ub_selection_user {
  my ($namepart, $need_bookmark_id) = @_;
  _sql_select_user_bookmark_id($need_bookmark_id, 'user AS user_id')
      .' FROM user_bookmark WHERE user = '.$namepart->obj_id_or_zero;
}

sub _sql_ub_selection_tag {
  my ($namepart, $need_bookmark_id) = @_;
  return 'SELECT user_bookmark AS user_bookmark_id FROM user_bookmark_tag WHERE tag = '.$namepart->obj_id_or_zero
      unless $need_bookmark_id;
  return 'SELECT ub.bookmark AS bookmark_id, ub.user_bookmark_id, ubt.tag AS tag_id FROM user_bookmark_tag ubt LEFT JOIN user_bookmark ub ON (ubt.user_bookmark = ub.user_bookmark_id) WHERE ubt.tag = '.$namepart->obj_id_or_zero;
}

sub _sql_ub_selection_gang {
  my ($namepart, $need_bookmark_id) = @_;
  _sql_select_user_bookmark_id($need_bookmark_id, 'ug.gang AS gang_id')
      .' FROM user_gang ug LEFT JOIN user_bookmark ub ON (ug.user = ub.user) WHERE ug.gang = '.$namepart->obj_id_or_zero;
}

sub _sql_ub_selection_date {
  my ($namepart, $need_bookmark_id) = @_;
  my $date = $namepart->obj->mysql_date;
  _sql_select_user_bookmark_id($need_bookmark_id, 'TO_DAYS(created) AS date_id')
      ." FROM user_bookmark WHERE created BETWEEN \'$date 00:00:00\' AND \'$date 23:59:59\'";
}

sub _sql_ub_selection_bookmark {
  my ($namepart, $need_bookmark_id) = @_;
  _sql_select_user_bookmark_id($need_bookmark_id, 'user AS user_id')
      .' FROM user_bookmark WHERE bookmark = '.$namepart->obj_id_or_zero;
}

sub _sql_user_tag_super_optimized {
  my ($user_namepart, $tag_namepart) = @_;
  my $user_id = $user_namepart->obj_id_or_zero;
  my $tag_id  = $tag_namepart->obj_id_or_zero;
  return "SELECT ub.user_bookmark_id FROM user_bookmark ub LEFT JOIN user_bookmark_tag ubt ON (ub.user_bookmark_id = ubt.user_bookmark) WHERE ub.user = $user_id AND ubt.tag = $tag_id";
}

sub _sql_user_date_super_optimized {
  my ($user_namepart, $date_namepart) = @_;
  my $user_id = $user_namepart->obj_id_or_zero;
  my $date    = $date_namepart->obj->mysql_date;
  return "SELECT user_bookmark_id FROM user_bookmark WHERE user = $user_id AND created BETWEEN \'$date 00:00:00\' AND \'$date 23:59:59\'";
}

sub _sql_user_bookmark_super_optimized {
  my ($user_namepart, $bookmark_namepart) = @_;
  my $user_id     = $user_namepart->obj_id_or_zero;
  my $bookmark_id = $bookmark_namepart->obj_id_or_zero;
  return "SELECT user_bookmark_id FROM user_bookmark WHERE user = $user_id AND bookmark = $bookmark_id";
}

sub _sql_user_gang_super_optimized {
  my ($user_namepart, $gang_namepart) = @_;
  my $user_id = $user_namepart->obj_id_or_zero;
  my $gang_id = $gang_namepart->obj_id_or_zero;
  return "SELECT ub.user_bookmark_id FROM user_gang ug INNER JOIN user_bookmark ub ON (ug.user = ub.user) WHERE ug.user = $user_id AND ug.gang = $gang_id";
}

sub _sql_tag_date_super_optimized {
  my ($tag_namepart, $date_namepart) = @_;
  my $tag_id = $tag_namepart->obj_id_or_zero;
  my $date   = $date_namepart->obj->mysql_date;
  return "SELECT ub.user_bookmark_id FROM user_bookmark ub LEFT JOIN user_bookmark_tag ubt ON (ub.user_bookmark_id = ubt.user_bookmark) WHERE ubt.tag = $tag_id AND ub.created BETWEEN \'$date 00:00:00\' AND \'$date 23:59:59\'";
}

sub _sql_tag_bookmark_super_optimized {
  my ($tag_namepart, $bookmark_namepart) = @_;
  my $tag_id      = $tag_namepart->obj_id_or_zero;
  my $bookmark_id = $bookmark_namepart->obj_id_or_zero;
  return "SELECT ub.user_bookmark_id FROM user_bookmark ub LEFT JOIN user_bookmark_tag ubt ON (ub.user_bookmark_id = ubt.user_bookmark) WHERE ubt.tag = $tag_id AND ub.bookmark = $bookmark_id";
}

sub _sql_gang_tag_super_optimized {
  my ($gang_namepart, $tag_namepart) = @_;
  my $gang_id = $gang_namepart->obj_id_or_zero;
  my $tag_id  = $tag_namepart->obj_id_or_zero;
  return "SELECT ub.user_bookmark_id FROM user_gang ug INNER JOIN user_bookmark ub ON (ug.user = ub.user) LEFT JOIN user_bookmark_tag ubt ON (ub.user_bookmark_id = ubt.user_bookmark) WHERE ug.gang = $gang_id AND ubt.tag = $tag_id";
}

sub _sql_gang_date_super_optimized {
  my ($gang_namepart, $date_namepart) = @_;
  my $gang_id = $gang_namepart->obj_id_or_zero;
  my $date    = $date_namepart->obj->mysql_date;
  return "SELECT ub.user_bookmark_id FROM user_gang ug INNER JOIN user_bookmark ub ON (ug.user = ub.user) WHERE ug.gang = $gang_id AND ub.created BETWEEN \'$date 00:00:00\' AND \'$date 23:59:59\'";
}

sub _sql_date_bookmark_super_optimized {
  my ($date_namepart, $bookmark_namepart) = @_;
  my $date        = $date_namepart->obj->mysql_date;
  my $bookmark_id = $bookmark_namepart->obj_id_or_zero;
  return "SELECT user_bookmark_id FROM user_bookmark WHERE bookmark = $bookmark_id AND created BETWEEN \'$date 00:00:00\' AND \'$date 23:59:59\'";
}

sub _sql_gang_bookmark_super_optimized {
  my ($gang_namepart, $bookmark_namepart) = @_;
  my $gang_id     = $gang_namepart->obj_id_or_zero;
  my $bookmark_id = $bookmark_namepart->obj_id_or_zero;
  return "SELECT ub.user_bookmark_id FROM user_gang ug INNER JOIN user_bookmark ub ON (ug.user = ub.user) WHERE ug.gang = $gang_id AND ub.bookmark = $bookmark_id";
}

sub _sql_super_optimized {
  my ($earlier_filter, $earlier_namepart, $later_filter, $later_namepart) = @_;
  my $sql = eval "_sql_${earlier_filter}_${later_filter}_super_optimized(\$earlier_namepart, \$later_namepart)";
  die $@ if $@;
  return $sql;
}

sub _sql_ub_selection {
  my ($namepart, $need_bookmark_id) = @_;

  defined $namepart or die 'no namepart';
  UNIVERSAL::isa($namepart, 'Bibliotech::Parser::NamePart') or die 'namepart is wrong type: '.ref($namepart);
  defined $need_bookmark_id or die 'no need_bookmark_id flag';

  my $class = $namepart->class;
  return _sql_ub_selection_user($namepart, $need_bookmark_id)     if $class eq 'Bibliotech::User';
  return _sql_ub_selection_user($namepart, $need_bookmark_id)     if $class eq 'Bibliotech::User';
  return _sql_ub_selection_tag($namepart, $need_bookmark_id)      if $class eq 'Bibliotech::Tag';
  return _sql_ub_selection_gang($namepart, $need_bookmark_id)     if $class eq 'Bibliotech::Gang';
  return _sql_ub_selection_date($namepart, $need_bookmark_id)     if $class eq 'Bibliotech::Date';
  return _sql_ub_selection_bookmark($namepart, $need_bookmark_id) if $class eq 'Bibliotech::Bookmark';
  die "_sql_ub_selection unhandled class ($class)";
}

sub _sql_get_user_bookmark_ids_for_one_criterion {
  my $namepart = shift;
  _sql_ub_selection($namepart, 0);
}

sub _sql_get_user_bookmark_ids_and_bookmark_ids_for_one_criterion {
  my $namepart = shift;
  _sql_ub_selection($namepart, 1);
}

sub _sql_get_all_user_bookmark_ids {
  'SELECT user_bookmark_id FROM user_bookmark';
}

sub _search_ub_optimized_sql_select_user_bookmark_ids_only {
  my ($output, $get_namepartset, $filters_used, $is_two_filters_used_once) = @_;
      
  return _sql_super_optimized(map { $_ => @{$get_namepartset->($_)} } $filters_used->()) if $is_two_filters_used_once->();

  my $OR_ub  = sub { _sql_union    (@_) };
  my $AND_ub = sub { _sql_intersect(('user_bookmark_id') x 4, @_) };
  my $AND_b  = sub { my $filter = shift;
		     my $needs_merge_on_bookmark_id = $filter =~ /^(?:user|gang|date)$/ && @_ > 1;
		     return $AND_ub->(map { $_->(0) } @_) unless $needs_merge_on_bookmark_id;
                     _sql_intersect('MAX(user_bookmark_id) AS user_bookmark_id',
				    "bookmark_id, user_bookmark_id, ${filter}_id",
				    'bookmark_id',
				    "DISTINCT ${filter}_id",
				    map { $_->(1) } @_) };
  my $ALL    = sub { local $_ = shift; ref $_ eq 'ARRAY' ? @{$_} : ($_) };
  my $nameparts_specified = sub { local $_ = shift;
				  @{add_geotagged_tag_to_namepart_set($output, $_, $get_namepartset->($_) || [])} };

  return $AND_ub->(map { my $filter = $_;      # AND the filters: /user/martin/tag/perl = martin AND perl
           $OR_ub->(map { my $slashpart = $_;  # OR the parts of a filter: /user/martin/ben = martin OR ben
     	     $AND_b->($filter,                 # AND the plus'd parts: /user/martin+ben = martin AND ben
     		      map { my $namepart = $_;
			    sub { $_[0]
				  ? _sql_get_user_bookmark_ids_and_bookmark_ids_for_one_criterion($namepart)
				  : _sql_get_user_bookmark_ids_for_one_criterion($namepart)
				};
     	     } $ALL->($slashpart))
     	   } $nameparts_specified->($filter))
         } $filters_used->())
         || _sql_get_all_user_bookmark_ids();
}

sub _search_ub_optimized_sql_select_user_bookmark_ids_only_using_command {
  my $command = shift;
  return _search_ub_optimized_sql_select_user_bookmark_ids_only
      ($command->output,
       sub { my $filter = shift; $command->$filter },
       sub { $command->filters_used },
       sub { (my @filters_used = $command->filters_used) == 2  or return;
	     $command->filters_used_only_single(@filters_used) or return;
	     return 1; },
      );
}

sub _search_ub_optimized_count {
  my ($sql_select_user_bookmark_ids_only_with_privacy, $privacybind_ref) = @_;

  my $sth = Bibliotech::User_Bookmark->psql_packed_count_query_using_subselect
      ($sql_select_user_bookmark_ids_only_with_privacy);
  Bibliotech::Profile::start('query object waiting for mysql for count (_search_ub_optimized)');
  eval { $sth->execute(@{$privacybind_ref}) or die $sth->errstr };
  die "count execute died: $@" if $@;
  my ($count) = $sth->fetchrow_array;
  $sth->finish;
  Bibliotech::Profile::stop();

  return $count;
}

sub _search_ub_optimized_data {
  my ($sql_select_user_bookmark_ids_only_with_privacy, $privacywhere, $privacybind_ref, $activeuser, $sort, $sortdir, $start, $num) = @_;

  my @select       = Bibliotech::User_Bookmark->packed_select;
  my $limit        = join(' ', 'LIMIT', int($start).',', int($num) || 100000);
  my $orderby      = join(' ', 'ORDER BY', $sort || 'ub.created', $sortdir || 'DESC');
  my @privacybind  = @{$privacybind_ref};
  (my $ubo_orderby = $orderby) =~ s/\bub\./ubo./g;
  Bibliotech::Profile::start('_search_ub_optimized_data creating temp table qq2');
  my $qq2 = join(' ', $sql_select_user_bookmark_ids_only_with_privacy, $ubo_orderby, $limit);
  my $dbh = Bibliotech::DBI->db_Main;
  eval {
    eval { $dbh->do('DROP TEMPORARY TABLE IF EXISTS qq2'); };  # for buggy situations
    die 'dropping temporary table qq2: '.$@ if $@;
    eval { $dbh->do($QQ2 = 'CREATE TEMPORARY TABLE qq2 AS '.$qq2, undef, @privacybind) or die 'failed qq2 creation'; };
    die 'creating temporary table qq2: '.$@ if $@;
    eval { $dbh->do('ALTER TABLE qq2 ADD INDEX user_bookmark_id_idx (user_bookmark_id)') or die 'failed qq2 indexing'; };
    die 'adding index to qq2: '.$@ if $@;
  };
  die "setting up qq2: $@" if $@;
  Bibliotech::Profile::stop();

  my $sth = Bibliotech::User_Bookmark->psql_packed_query_using_subselect  # <----- cross-ref this in Bibliotech::DBI
      (join(', ', @select),
       'qq2',
       $privacywhere,
       $orderby);

  Bibliotech::Profile::start('query object waiting for mysql for data (_search_ub_optimized)');
  my $activeuser_id = eval { return 0 unless defined $activeuser;
			     return $activeuser unless ref $activeuser;
			     return $activeuser->user_id;
			   };
  eval { $sth->execute(@privacybind, $activeuser_id) or die $sth->errstr };
  die "data execute died: $@" if $@;
  my @data = @{$sth->fetchall_arrayref};
  Bibliotech::Profile::stop();

  Bibliotech::Profile::start('converting packed arrays to user_bookmark objects');
  my $names_ref = Bibliotech::User_Bookmark->select2names(\@select);
  my $set = Bibliotech::DBI::Set->new(map { Bibliotech::User_Bookmark->unpack_packed_select($names_ref, $_) }
				      map { bless($_, 'Bibliotech::DBI::Set::Line') }
				      @data);
  Bibliotech::Profile::stop();

  return ($set,
	  sum map { $_->is_geotagged || 0 } @{$set});  # geocount
}

sub _search_ub_optimized_sql_select_user_bookmark_ids_only_with_privacy {
  my ($sql_select_user_bookmark_ids_only, $privacywhere) = @_;
  (my $ubo_privacywhere = $privacywhere) =~ s/\bub\./ubo./g;
  return "SELECT ubs.user_bookmark_id FROM ($sql_select_user_bookmark_ids_only) AS ubs ".
         "NATURAL JOIN user_bookmark ubo WHERE $ubo_privacywhere AND ubo.user_bookmark_id IS NOT NULL";
}

sub _search_ub_optimized_sql_select_user_bookmark_ids_only_with_privacy_qq {
  my ($sql_select_user_bookmark_ids_only, $privacywhere) = @_;
  if ($sql_select_user_bookmark_ids_only eq 'SELECT user_bookmark_id FROM user_bookmark') {
    (my $ubo_privacywhere = $privacywhere) =~ s/\bub\./ubo./g;
    return "SELECT ubo.user_bookmark_id FROM user_bookmark AS ubo WHERE $ubo_privacywhere";
  }
  else {
    my $dbh = Bibliotech::DBI->db_Main;
    eval {
      eval { $dbh->do('DROP TEMPORARY TABLE IF EXISTS qq1'); };  # for buggy situations
      die 'dropping temporary table qq1: '.$@ if $@;
      eval { $dbh->do($QQ1 = 'CREATE TEMPORARY TABLE qq1 AS '.$sql_select_user_bookmark_ids_only) or die 'failed qq1 creation'; };
      die 'creating temporary table qq1: '.$@ if $@;
      eval { $dbh->do('ALTER TABLE qq1 ADD INDEX user_bookmark_id_idx (user_bookmark_id)') or die 'failed qq1 indexing'; };
      die 'adding index to qq1: '.$@ if $@;
    };
    die "setting up qq1: $@" if $@;
  }
  (my $ubo_privacywhere = $privacywhere) =~ s/\bub\./ubo./g;
  return "SELECT ubs.user_bookmark_id FROM qq1 AS ubs ".
         "NATURAL JOIN user_bookmark ubo WHERE $ubo_privacywhere AND ubo.user_bookmark_id IS NOT NULL";
}

# _search_ub_optimized does the same as _search() provided that there
# are no options to _search() in excess of the parameters that
# _search_ub_optimized() accepts, except class which must be
# 'Bibliotech::User_Bookmark'.
sub _search_ub_optimized {
  my ($self, $activeuser, $sort, $sortdir, $start, $num) = @_;

  Bibliotech::Profile::start(sub { join(' ',
					'_search_ub_optimized:',
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

    Bibliotech::Profile::start('_search_ub_optimized creating temp table qq1');

    my ($privacywhere, @privacybind) = $self->privacywhere($activeuser);
    my $sql_select_user_bookmark_ids_only_with_privacy =
	_search_ub_optimized_sql_select_user_bookmark_ids_only_with_privacy_qq
	(_search_ub_optimized_sql_select_user_bookmark_ids_only_using_command($self->command),
	 $privacywhere);

    Bibliotech::Profile::stop();

    ($set, $geocount) = _search_ub_optimized_data ($sql_select_user_bookmark_ids_only_with_privacy,
						   $privacywhere, \@privacybind,
						   $activeuser, $sort, $sortdir, $start, $num);
    $count            = _search_ub_optimized_count($sql_select_user_bookmark_ids_only_with_privacy,
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
  my $subselect = _search_ub_optimized_sql_select_user_bookmark_ids_only_with_privacy(_search_ub_optimized_sql_select_user_bookmark_ids_only_using_command($self->command), $privacywhere);
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
  my $sql = "SELECT COUNT(ubjg.user_bookmark_id) FROM (%s) AS ubjg";
  return $self->_full_count('count', $activeuser, $sql);
}

sub full_geocount {
  my ($self, $activeuser) = @_;
  my $tag_id = geotagged_tag_namepart()->obj_id_or_zero or return 0;
  my $sql = "SELECT COUNT(ubjg.user_bookmark_id) FROM (%s) AS ubjg LEFT JOIN user_bookmark_tag ubt ON (ubjg.user_bookmark_id = ubt.user_bookmark) WHERE ubt.tag = ?";
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
    unless ($options{class} ne 'Bibliotech::User_Bookmark' or
	    $options{freematch} or
	    $self->freematch or
	    $options{no_freematch} or
	    $options{all} or
	    $options{forcegroup} or
	    $options{where} or
	    $options{having}) {
      my ($optimized_count, $optimized_geocount);
      ($final_set, $optimized_count, $optimized_geocount) = 
	  $self->_search_ub_optimized($options{activeuser} || $self->activeuser,
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
    
    # for each of various keys (USER BOOKMARK TAG DATE) there can zero or more search matches
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
      if ($group eq 'ub.user_bookmark_id' and !$self->command->filters_used) {
	foreach (@select) {
	  s/^$alias_primary$/MAX($alias_primary)/;
	}
	$group = 'b.bookmark_id';
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
	  if ($alias eq 'ub' and (ref $match or $key eq 'DUMMY')) {
	    @thisselect[0] = "MAX($alias_primary)";
	    $thisgroupby = 'GROUP BY b.bookmark_id';
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
	    if ($thisselect =~ /\b(ub|u|b|t|g)\./) {
	      $sql_options{join_ub} = $privacywhere;
	      $sql_options{bind_ub} = \@privacybind;
	    }
	    if ($thisselect =~ /\bub2\./) {
	      (my $ub2_privacywhere = $privacywhere) =~ s/ub\./ub2\./g;
	      $sql_options{join_ub2} = $ub2_privacywhere;
	      $sql_options{bind_ub2} = \@privacybind;
	    }
	    if ($thisselect =~ /\bub3\./) {
	      $sql_options{join_ub3} = 'ub3.user = ?';
	      $sql_options{bind_ub3} = [$activeuser ? $activeuser->user_id : 0];
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
	      die "$@\nSQL is:\n----------\n$sql\n----------\n\n".Dumper(\%sql_options, \@sql_execute);
	    }
	  }
	  else {
	    $or_item_set = Bibliotech::DBI::Set->new
		            (map { bless $_, 'Bibliotech::DBI::Set::Line'; } @{$sth->fetchall_arrayref});
	  }

	  if ($use_limit_shortcut) {
	    eval {
	      my $distinct = 'ub.user_bookmark_id';
	      if ($thisgroupby =~ /^GROUP BY ub\.(\w+)/ or
		  $thisgroupby =~ /^GROUP BY b\.(bookmark)_id/ or
		  $thisgroupby =~ /^GROUP BY u\.(user)_id/) {
		$distinct = 'ub.'.$1;
	      }
	      my $count_sql;
	      my @count_bind;
	      my $special_additions = @freematch || $options{where} || $options{having};
	      if (!$self->command->filters_used and !$special_additions) {
		$count_sql = "SELECT COUNT(DISTINCT $distinct) FROM user_bookmark ub WHERE $privacywhere";
		@count_bind = @privacybind;
	      }
	      #elsif ($key eq 'DATE' and !$special_additions) {
	        #$count_sql = "SELECT COUNT(DISTINCT $distinct) FROM user_bookmark ub WHERE $where AND $privacywhere";
	        #@count_bind = (@wbind, @privacybind);
	      #}
	      elsif ($key eq 'BOOKMARK' and !$special_additions) {
		$count_sql = "SELECT COUNT(DISTINCT $distinct) FROM user_bookmark ub LEFT JOIN bookmark b ON (ub.bookmark=b.bookmark_id) WHERE $where AND $privacywhere";
		@count_bind = (@wbind, @privacybind);
	      }
	      else {
		%sql_options = (count => 1,
				class => $class,
				select => ["COUNT(DISTINCT $distinct)"],
				join_ub => $privacywhere,
				bind_ub => \@privacybind,
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
      if ($select[$i] =~ /ub_is_geotagged/) {
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

sub users {
  shift->_search(class => 'Bibliotech::User', @_);
}

sub gangs {
  shift->_search(class => 'Bibliotech::Gang', @_);
}

sub bookmarks {
  shift->_search(class => 'Bibliotech::Bookmark', @_);
}

sub tags {
  shift->_search(class => 'Bibliotech::Tag', @_);
}

sub user_bookmarks {
  shift->_search(class => 'Bibliotech::User_Bookmark', @_);
}

sub recent {
  shift->user_bookmarks(@_);
}

sub popular {
  shift->user_bookmarks(sort => 'COUNT(DISTINCT ub.user)', @_);
}

sub home {
  shift->user_bookmarks(@_);
}

1;
__END__
