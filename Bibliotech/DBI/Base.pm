package Bibliotech::DBI;
use strict;
use base 'Class::DBI';
use List::MoreUtils qw/any/;
use Data::Dumper;
use Encode qw/encode_utf8 decode_utf8 decode is_utf8/;
use Bibliotech::Config;
use Bibliotech::Util;
use Bibliotech::FilterNames;

our $DBI_CONNECT  = Bibliotech::Config->get_required('DBI_CONNECT');
our $DBI_USERNAME = Bibliotech::Config->get('DBI_USERNAME');
our $DBI_PASSWORD = Bibliotech::Config->get('DBI_PASSWORD');
our $DBI_SEARCH   = Bibliotech::Config->get('DBI_SEARCH');
our $DBI_SEARCH_DOT_OR_BLANK = $DBI_SEARCH ? $DBI_SEARCH.'.' : '';
our $DEBUG_WARN_SQL = 0;

__PACKAGE__->connection($DBI_CONNECT, $DBI_USERNAME, $DBI_PASSWORD);

__PACKAGE__->purge_object_index_every(5000);

__PACKAGE__->add_constructor(since => 'created > ?');
__PACKAGE__->add_constructor(recent => 'created > NOW() - INTERVAL 7 DAY');
__PACKAGE__->columns(TEMP => qw/sortvalue/);

# create a way to use Class::DBI but with case insensitive search() and find_or_create()
__PACKAGE__->add_searcher(isearch => 'Bibliotech::DBI::Class::DBI::Search::CaseInsensitive');
sub ifind_or_create {
  my $class    = shift;
  my $hash     = ref $_[0] eq "HASH" ? shift: {@_};
  my ($exists) = $class->isearch($hash);
  return defined($exists) ? $exists : $class->insert($hash);
}

sub stringify_self {
  my $self = shift;
  return overload::StrVal($self) if caller(1) =~ /^(?:Data|Devel)::/;  # react normally to introspective modules
  return $self->SUPER::stringify_self;
}

sub activate_warn_sql {
  $DEBUG_WARN_SQL = 1;
}

sub deactivate_warn_sql {
  $DEBUG_WARN_SQL = 0;
}

sub debug_warn_sql {
  return unless $DEBUG_WARN_SQL;
  warn "\n", "Running SQL:\n", @_, "\n";
}

# Copied in from Ima::DBI 0.34 and edited to add one debug line so we can see SQL statements
sub _mk_sql_closure {
	my ($class, $sql_name, $statement, $db_meth, $cache) = @_;

	return sub {
		my $class = shift;
		my $dbh   = $class->$db_meth();

		# Everything must pass through sprintf, even if @_ is empty.
		# This is to do proper '%%' translation.
		my $sql = $class->transform_sql($statement => @_);
		debug_warn_sql($sql);
		return $cache
			? $dbh->prepare_cached($sql)
			: $dbh->prepare($sql);
	};
}

# setup sub for classes to call to indicate that columns can contain UTF-8 and should be decoded after select
sub force_utf8_columns {
  my ($class, @columns) = @_;
  $class->add_trigger(select => sub { my ($self) = @_;
				      foreach (@columns) {
					$self->{$_} = decode_utf8($self->{$_}) ||
					    decode('iso-8859-1', $self->{$_}) ||
					    $self->{$_}
					  if $self->{$_} && !is_utf8($self->{$_});
				      }
				    });
  $class->add_trigger(before_create => sub { my ($self) = @_;
					     foreach (@columns) {
					       $self->{$_} = decode_utf8($self->{$_}) ||
						   decode_utf8(encode_utf8($self->{$_})) ||
						   $self->{$_}
					       if $self->{$_} && !is_utf8($self->{$_});
				      }
				    });
}

# setup sub for classes to call to define datetime columns
# makes them inflate to Time::Piece objects
sub datetime_column {
  my ($self, $column, $set_on_trigger, $format) = @_;
  $self->has_a($column => 'Bibliotech::Date', inflate => 'new', deflate => 'mysql_'.($format || 'datetime'));
  $self->add_trigger($set_on_trigger => sub { shift->set_datetime_now($column); }) if $set_on_trigger;
}

sub set_datetime_now {
  my ($self, $column) = @_;
  $self->$column(Bibliotech::Date->mysql_now);
}

sub mark_updated {
  my $self = shift;
  $self->set_datetime_now('updated');
  $self->update;
  return $self;
}

# inherited sub
# like search or find_or_create, except it can accept:
# (a) an object, in which case it passes it through
# (b) a hash, in which case it creates a new object
# (c) just a scalar for the 2nd column (e.g. the name column for a tag which is really all you need), same as b
sub new {
  my ($class, $obj, $create) = @_;
  return $obj if UNIVERSAL::isa($obj, $class);
  my $func = ('search', 'find_or_create', 'create', 'isearch', 'ifind_or_create')[int($create || 0)];
  if ($func eq 'search' and $class->can('search_new')) {
    return $class->search_new($obj);
  }
  my @result = $class->$func({$class->unique => $obj});
  die 'ambiguous result' if @result > 1;
  if (!@result and my $secondary = $class->another_index) {
    @result = $class->$func({$secondary => $obj});
    die 'ambiguous result' if @result > 1;
  }
  return $result[0];
}

sub transfer {
  my ($class, $obj, $replacement_ref, $extra_methods_ref, $func, $test_flag) = @_;
  $replacement_ref ||= {};
  $func ||= 'find_or_create';
  my %values;
  my %report;
  foreach ($extra_methods_ref ? @{$extra_methods_ref} : (),
	   $class->columns) {
    if (exists $replacement_ref->{$_}) {
      $values{$_} = $replacement_ref->{$_};
      $report{$_} = 'discovered in replacement values';
    }
    elsif (UNIVERSAL::can($obj, $_) or UNIVERSAL::can($obj, 'AUTOLOAD')) {
      eval {
	$values{$_} = $obj->$_;
      };
      $report{$_} = 'discovered in original object';
      $report{$_} .= " ($@)" if $@;
    }
    else {
      $report{$_} = 'not discovered';
    }
  }
  die 'transfer from '.ref($obj)." to $class attempted with no values: ".Dumper($obj, \%report) unless %values;
  die Dumper(\%report) if $test_flag;
  my $newobj = $class->$func(\%values);
  #warn Dumper($newobj);
  return $newobj;
}

# more advanced transfer
sub clone {
  my ($class, $obj, $test_flag) = @_;
  return $class->transfer($obj, {$class->primary_column => undef}, undef, 'construct', $test_flag);
}

# given a user_article and a list of tags this function can update the user_article_tag rows as needed
# by comparing the names of the existing and new tags so as to only delete the obsolete rows and only
# create the additional rows
# e.g.: $self->update_links_one_to_many($add, $user_article, 'tag', $tags_ref);
sub update_links_one_to_many {
  my ($one,          # the "one" from which to make many; e.g. the user_article object
      $manyclass,    # a string representing the "many" entity class; e.g. 'Bibliotech::Tag'
      $newlist_ref,  # the new list of the "many", by object or label string; e.g. ('newtag1','newtag2')
      ) = @_;

  my $manyentity = $manyclass->table;      # e.g. 'tag'
  my $manyfunc   = $manyentity.'s';        # method name to be called on $one
  my $linkfunc   = 'link_'.$manyentity;    # method name to be called on $one
  my $unlinkfunc = 'unlink_'.$manyentity;  # method name to be called on $one

  # for existing set, we used to ask add/edit and only populate on edit, but we found some people
  # posting 'add' even when a user_article exists, so this way we clobber the old data in that case

  # find out what tags already exist and get names ready for the new set
  my $existing   = Bibliotech::DBI::Set->new($one->$manyfunc);
  my $new        = Bibliotech::DBI::Set->new(map { $manyclass->new($_, 1) } @{$newlist_ref});
  # calculate what stays and goes
  my @additional = $new->difference($existing);
  my @obsolete   = $existing->difference($new);
  # perform the acts
  $one->$linkfunc(@additional) if @additional;
  $one->$unlinkfunc(@obsolete) if @obsolete;
  # return the one
  return $one;
}

# called by worker functions that have been passed an options hash that may contain id's or real objects
sub normalize_option {
  my ($self, $options_ref, %myoptions) = @_;
  my $field = $myoptions{field};
  my $optional = $myoptions{optional};
  my $blank_for_undef = $myoptions{blank_for_undef};
  my $default_fields_ref = $myoptions{default_fields};
  my $checksub = $myoptions{checksub};
  my $obj;
  my $table = $self->table;
  my $noun = $self->noun;
  my $found = 0;
  if (!defined($field) or $field eq $table) {
    foreach ($default_fields_ref
	     ? @{$default_fields_ref}
	     : ($self->primary_column, $table, $noun, 'private_'.$table, 'private_'.$noun)) {
      if (exists $options_ref->{$_}) {
	$obj = $options_ref->{$_};
	$found = 1;
	last;
      }
    }
  }
  else {
    $found = exists $options_ref->{$field};
    $obj = $options_ref->{$field};
  }
  unless (defined $obj) {
    return '' if $optional && $blank_for_undef && $found;
    return if $optional;
    die "You must specify a $noun.\n";
  }
  my $class = ref($self) || $self;
  unless (UNIVERSAL::isa($obj, $class)) {
    if ($obj =~ /^\d+$/) {
      $obj = $class->retrieve($obj) or die "Unknown $noun $obj.\n";
    }
    else {
      my $name = $obj;
      if (defined $checksub) {
	$checksub->($name);
      }
      $obj = $class->new($name) or die "Unknown $noun $name.\n";
    }
  }
  return $obj;
}

sub unique {
  shift->primary_column;  # will be OVERRIDDEN to a non-primary column in every applicable class!
}

sub unique_value {
  my $self = shift;
  my $method = $self->unique;
  return $self->$method;
}

sub noun {
  shift->table;
}

sub another_index {
  undef;
}

sub div_id {
  my $self = shift;
  my $id = $self->table.'_'.$self->unique_value;
  $id =~ s/\W/_/g;
  return $id;
}

# used by packed_select()'s below
sub packing_essentials {
  my ($class, $alias) = @_;
  $alias ||= eval { $class->my_alias; };
  if ($@) {
    require Carp;
    Carp::confess $@;
  }
  return map("$alias.$_", $class->_essential);
}

# used by packed_select()'s below
sub packing_groupconcat {
  my ($class, $alias, $select_alias, $order) = @_;
  $alias ||= $class->my_alias;
  my @essential = $class->_essential;
  my $primary = shift @essential;
  # CONCAT() in next line is at the advice of: http://bugs.mysql.com/bug.php?id=10619
  my $select = join(",\':/:\',", "CONCAT($alias.$primary)", map("IFNULL($alias.$_, \'+NULL\')", @essential));
  $select .= " ORDER BY $order" if $order;
  my $func = "IFNULL(GROUP_CONCAT(DISTINCT $select SEPARATOR \'///\'), \'\')";
  $func .= " AS $select_alias" if $select_alias;
  return $func;
}

sub freematch_one_term {
  my ($self, $term) = @_;
  my $search_database = $DBI_SEARCH_DOT_OR_BLANK;
  # if you edit the query, be sure to change the return statement that sets up the binding parameters
  # sql union components included below in order (order is by descending score):
  #   user_article_details title= [score 100]
  #   bookmark_details title= [score 100]
  #   citation title= (link thru bookmark to user_article) [score 99]
  #   citation title= (link to user_article) [score 99]
  #   journal name= (link citation thru bookmark to user_article) [score 98]
  #   journal name= (link citation to user_article) [score 98]
  #   journal medline_ta= (link citation thru bookmark to user_article) [score 98]
  #   journal medline_ta= (link citation to user_article) [score 98]
  #   author lastname= (link citation thru bookmark to user_article) [score 97]
  #   author lastname= (link citation to user_article) [score 97]
  #   user_article_details MATCH(title) [score 50]
  #   bookmark_details MATCH(title) [score 50]
  #   citation MATCH(title) (link thru bookmark to user_article) [score 49]
  #   citation MATCH(title) (link to user_article) [score 49]
  #   journal MATCH(name) (link citation thru bookmark to user_article) [score 48]
  #   journal MATCH(name) (link citation to user_article) [score 48]
  #   journal MATCH(medline_ta) (link citation thru bookmark to user_article) [score 48]
  #   journal MATCH(medline_ta) (link citation to user_article) [score 48]
  #   bookmark MATCH(url) [score 47]
  #   user_article_details MATCH(description) [score 45]
  #   comment MATCH(entry) [score 44]
  #   author MATCH(lastname, forename, firstname) (link citation thru bookmark to user_article) [score 43]
  #   author MATCH(lastname, forename, firstname) (link citation to user_article) [score 43]
  #   tag name= [score 20]
  #   tag MATCH(name) [score 20]
  my $sql = <<EOS;
SELECT   uad_s.user_article_id, 100 as score
FROM     user_article_details uad_s
WHERE    uad_s.title = ?
UNION
SELECT   ua.user_article_id, 100 as score
FROM     bookmark_details bd_s
         LEFT JOIN bookmark b_s ON (bd_s.bookmark_id=b_s.bookmark_id)
         LEFT JOIN user_article ua ON (b_s.article=ua.article)
WHERE    bd_s.title = ? AND b_s.bookmark_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 99 as score
FROM     citation c_s
         LEFT JOIN bookmark b_s ON (b_s.citation=c_s.citation_id)
         LEFT JOIN user_article ua ON (ua.article=b_s.article)
WHERE    c_s.title = ? AND b_s.bookmark_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 99 as score
FROM     citation c_s
         LEFT JOIN user_article ua ON (ua.citation=c_s.citation_id)
WHERE    c_s.title = ? AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 98 as score
FROM     journal j_s
         LEFT JOIN citation c_s ON (c_s.journal=j_s.journal_id)
         LEFT JOIN bookmark b_s ON (b_s.citation=c_s.citation_id)
	 LEFT JOIN article a_s ON (b_s.article=a_s.article_id)
         LEFT JOIN user_article ua ON (ua.article=a_s.article_id)
WHERE    j_s.name = ? AND c_s.citation_id IS NOT NULL AND b_s.bookmark_id IS NOT NULL AND a_s.article_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 98 as score
FROM     journal j_s
         LEFT JOIN citation c_s ON (c_s.journal=j_s.journal_id)
         LEFT JOIN user_article ua ON (ua.citation=c_s.citation_id)
WHERE    j_s.name = ? AND c_s.citation_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 98 as score
FROM     journal j_s
         LEFT JOIN citation c_s ON (c_s.journal=j_s.journal_id)
         LEFT JOIN bookmark b_s ON (b_s.citation=c_s.citation_id)
	 LEFT JOIN article a_s ON (b_s.article=a_s.article_id)
         LEFT JOIN user_article ua ON (ua.article=a_s.article_id)
WHERE    j_s.medline_ta = ? AND c_s.citation_id IS NOT NULL AND b_s.bookmark_id IS NOT NULL AND a_s.article_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 98 as score
FROM     journal j_s
         LEFT JOIN citation c_s ON (c_s.journal=j_s.journal_id)
         LEFT JOIN user_article ua ON (ua.citation=c_s.citation_id)
WHERE    j_s.medline_ta = ? AND c_s.citation_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 97 as score
FROM     author au_s
         LEFT JOIN citation_author cta_s ON (au_s.author_id=cta_s.author)
         LEFT JOIN citation c_s ON (c_s.citation_id=cta_s.citation)
         LEFT JOIN bookmark b_s ON (b_s.citation=c_s.citation_id)
	 LEFT JOIN article a_s ON (b_s.article=a_s.article_id)
         LEFT JOIN user_article ua ON (ua.article=a_s.article_id)
WHERE    au_s.lastname = ? AND cta_s.citation_author_id IS NOT NULL AND c_s.citation_id IS NOT NULL AND b_s.bookmark_id IS NOT NULL AND a_s.article_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 97 as score
FROM     author au_s
         LEFT JOIN citation_author cta_s ON (au_s.author_id=cta_s.author)
         LEFT JOIN citation c_s ON (c_s.citation_id=cta_s.citation)
         LEFT JOIN user_article ua ON (ua.citation=c_s.citation_id)
WHERE    au_s.lastname = ? AND cta_s.citation_author_id IS NOT NULL AND c_s.citation_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   uad_s.user_article_id, 50 as score
FROM     ${search_database}user_article_details uad_s
WHERE    MATCH(uad_s.title) AGAINST (? IN BOOLEAN MODE)
UNION
SELECT   ua.user_article_id, 50 as score
FROM     ${search_database}bookmark_details bd_s
         LEFT JOIN bookmark b_s ON (bd_s.bookmark_id=b_s.bookmark_id)
         LEFT JOIN user_article ua ON (b_s.article=ua.article)
WHERE    MATCH(bd_s.title) AGAINST (? IN BOOLEAN MODE) AND b_s.bookmark_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 49 as score
FROM     ${search_database}citation c_s
         LEFT JOIN bookmark b_s ON (b_s.citation=c_s.citation_id)
	 LEFT JOIN article a_s ON (b_s.article=a_s.article_id)
         LEFT JOIN user_article ua ON (ua.article=a_s.article_id)
WHERE    MATCH(c_s.title) AGAINST (? IN BOOLEAN MODE) AND b_s.bookmark_id IS NOT NULL AND a_s.article_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 49 as score
FROM     ${search_database}citation c_s
         LEFT JOIN user_article ua ON (ua.citation=c_s.citation_id)
WHERE    MATCH(c_s.title) AGAINST (? IN BOOLEAN MODE) AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 48 as score
FROM     ${search_database}journal j_s
         LEFT JOIN citation c_s ON (c_s.journal=j_s.journal_id)
         LEFT JOIN bookmark b_s ON (b_s.citation=c_s.citation_id)
	 LEFT JOIN article a_s ON (b_s.article=a_s.article_id)
         LEFT JOIN user_article ua ON (ua.article=a_s.article_id)
WHERE    MATCH(j_s.name) AGAINST (? IN BOOLEAN MODE) AND c_s.citation_id IS NOT NULL AND b_s.bookmark_id IS NOT NULL AND a_s.article_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 48 as score
FROM     ${search_database}journal j_s
         LEFT JOIN citation c_s ON (c_s.journal=j_s.journal_id)
         LEFT JOIN user_article ua ON (ua.citation=c_s.citation_id)
WHERE    MATCH(j_s.name) AGAINST (? IN BOOLEAN MODE) AND c_s.citation_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 48 as score
FROM     ${search_database}journal j_s
         LEFT JOIN citation c_s ON (c_s.journal=j_s.journal_id)
         LEFT JOIN bookmark b_s ON (b_s.citation=c_s.citation_id)
	 LEFT JOIN article a_s ON (b_s.article=a_s.article_id)
         LEFT JOIN user_article ua ON (ua.article=a_s.article_id)
WHERE    MATCH(j_s.medline_ta) AGAINST (? IN BOOLEAN MODE) AND c_s.citation_id IS NOT NULL AND b_s.bookmark_id IS NOT NULL AND a_s.article_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 48 as score
FROM     ${search_database}journal j_s
         LEFT JOIN citation c_s ON (c_s.journal=j_s.journal_id)
         LEFT JOIN user_article ua ON (ua.citation=c_s.citation_id)
WHERE    MATCH(j_s.medline_ta) AGAINST (? IN BOOLEAN MODE) AND c_s.citation_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 47 as score
FROM     ${search_database}bookmark b_s
         LEFT JOIN article a_s ON (b_s.article=a_s.article_id)
         LEFT JOIN user_article ua ON (a_s.article_id=ua.article)
WHERE    MATCH(b_s.url) AGAINST (? IN BOOLEAN MODE) AND a_s.article_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   uad_s.user_article_id, 45 as score
FROM     ${search_database}user_article_details uad_s
WHERE    MATCH(uad_s.description) AGAINST (? IN BOOLEAN MODE)
UNION
SELECT   ua.user_article_id, 44 as score
FROM     ${search_database}comment c_s
         LEFT JOIN user_article_comment uac_s ON (c_s.comment_id=uac_s.comment)
         LEFT JOIN user_article ua ON (uac_s.user_article=ua.user_article_id)
WHERE    MATCH(c_s.entry) AGAINST (? IN BOOLEAN MODE) AND uac_s.user_article_comment_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 43 as score
FROM     ${search_database}author au_s
         LEFT JOIN citation_author cta_s ON (au_s.author_id=cta_s.author)
         LEFT JOIN citation c_s ON (c_s.citation_id=cta_s.citation)
         LEFT JOIN bookmark b_s ON (b_s.citation=c_s.citation_id)
	 LEFT JOIN article a_s ON (b_s.article=a_s.article_id)
         LEFT JOIN user_article ua ON (ua.article=a_s.article_id)
WHERE    MATCH(au_s.lastname, au_s.forename, au_s.firstname) AGAINST (? IN BOOLEAN MODE) AND cta_s.citation_author_id IS NOT NULL AND c_s.citation_id IS NOT NULL AND b_s.bookmark_id IS NOT NULL AND a_s.article_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 43 as score
FROM     ${search_database}author au_s
         LEFT JOIN citation_author cta_s ON (au_s.author_id=cta_s.author)
         LEFT JOIN citation c_s ON (c_s.citation_id=cta_s.citation)
         LEFT JOIN user_article ua ON (ua.citation=c_s.citation_id)
WHERE    MATCH(au_s.lastname, au_s.forename, au_s.firstname) AGAINST (? IN BOOLEAN MODE) AND cta_s.citation_author_id IS NOT NULL AND c_s.citation_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   uat_s.user_article as user_article_id, 20 as score
FROM     tag t_s
         LEFT JOIN user_article_tag uat_s ON (uat_s.tag=t_s.tag_id)
WHERE    t_s.name = ? AND uat_s.user_article_tag_id IS NOT NULL
UNION
SELECT   uat_s.user_article as user_article_id, 20 as score
FROM     ${search_database}tag t_s
         LEFT JOIN user_article_tag uat_s ON (uat_s.tag=t_s.tag_id)
WHERE    MATCH(t_s.name) AGAINST (? IN BOOLEAN MODE) AND uat_s.user_article_tag_id IS NOT NULL
EOS
  return ($sql, [($term) x 25]);  # the number of question marks above
}

sub freematch_all_terms {
  my $self = shift;
  my @terms = @_ or die 'freematch_all_terms called without terms';

  # convert a list of terms into a list of positive/negative flag, sql snippet, and parameter bind list per term
  my @selects;
  my $count_positive = 0;  # how many terms were not negated with a minus sign, must be at least one
  foreach my $term (@terms) {
    my $positive;
    if ($term =~ s/^\-//) {
      $positive = 0;
    }
    else {
      $term =~ s/^\+//;  # positive indication is just redundant
      $positive = 1;
      $count_positive++;
    }
    push @selects, [$positive, $self->freematch_one_term($term)];
  }

  die "You may not search on all negative terms.\n" unless $count_positive > 0;

  my $union_all_sql =
      join("\nUNION ALL\n",
	   map {
	     my ($positive, $sql, $bind) = @{$selects[$_]};
	     my $num = $_+1;
	     "SELECT user_article_id, MAX(score) as score, $positive as positive ".
	     "FROM ($sql) as fmot$num GROUP BY user_article_id";
	   } (0..$#selects));
  my @union_all_bind = map { @{$_->[2]}; } @selects;

  my $sql = <<EOS;
SELECT fmat.user_article_id, MAX(score)*1000000000+UNIX_TIMESTAMP(ua.created) as sortvalue
FROM
(
$union_all_sql
) as fmat
LEFT JOIN user_article ua ON (fmat.user_article_id=ua.user_article_id)
GROUP BY fmat.user_article_id
HAVING SUM(fmat.positive) = ? AND MIN(fmat.positive) = ?
EOS
  my @bind = (@union_all_bind, $count_positive, 1);

  return ($sql, \@bind);
}

sub _debug_pure_dump {
  $Data::Dumper::Purity = 1;
  die Dumper(@_);
}

sub sql_joined_dynamic {
  my $self = shift;
  my %options = @_;
  our (@classlist, %class, %alias);
  unless (@classlist) {
    # some repeat, that's ok
    @classlist = ('Bibliotech::User',
		  'Bibliotech::User_Article',
		  'Bibliotech::User_Article_Details',
		  'Bibliotech::Article',
		  'Bibliotech::Bookmark',
		  'Bibliotech::Bookmark_Details',
		  'Bibliotech::Citation',
		  'Bibliotech::Citation_Author',
		  'Bibliotech::Author',
		  'Bibliotech::Journal',
		  'Bibliotech::User_Article_Tag',
		  'Bibliotech::Tag',
		  'Bibliotech::User_Article_Comment',
		  'Bibliotech::Comment',
		  'Bibliotech::User_Gang',
		  'Bibliotech::Gang');
    foreach (@classlist) {
      my $alias = $_->my_alias;
      $alias{$_} = $alias;
      $class{$alias} = $_;
    }
  }
  my @select_bind = $options{select_bind} ? @{$options{select_bind}} : ();
  my $select = ref $options{select} ? join(', ', @{$options{select}}) : $options{select};
  my $where = ref $options{where} ? join(', ', @{$options{where}}) : $options{where};
  my @where_bind = $options{wbind} ? @{$options{wbind}} : ();
  my $having = ref $options{where} ? join(', ', @{$options{having}}) : $options{having};
  my @having_bind = $options{hbind} ? @{$options{hbind}} : ();
  my $group_by = ref $options{group_by} ? join(', ', @{$options{group_by}}) : $options{group_by};
  my $order_by = ref $options{order_by} ? join(', ', @{$options{order_by}}) : $options{order_by};
  my $limit = $options{limit};
  my %table;
  my $firsttable;
  $firsttable = 'u' if $where =~ /\bu\.user_id\s?=/;
  foreach ($where, $select) {
    while (/([a-zA-Z_]+)(\d*(_s)?)\.\w+/g) {
      $table{$1.($2 || '')} = 1;
      $firsttable ||= $1;
    }
  }
  $table{'ua'} ||= 1;
  $firsttable = 'ua' if !$firsttable or $firsttable =~ /_s$/;
  my @tableorder = ($firsttable);
  my %forceback;
  my %to_ua = (ua => [],
	       u => ['ua'],
	       a => ['ua'],
	       b => ['a', 'ua'],
	       t => ['uat', 'ua'],
	       g => ['ug', 'u', 'ua']);
  my $to_ua = $to_ua{$firsttable} or die "do not know how to get from $firsttable to ua";
  push @tableorder, @{$to_ua}, '*';
  if ($tableorder[0] eq 'ua' and $options{class} eq 'Bibliotech::User_Article') {
    unshift @tableorder, 'uap';
  }
  foreach (@tableorder) {
    delete $table{$_};
  }
  if ($table{u}) {
    push @tableorder, 'u';
    delete $table{u};
  }
  if ($table{t2}) {
    push @tableorder, 'uat2', 't2';
    delete $table{uat2};
    delete $table{t2};
  }
  if ($table{uad}) {
    push @tableorder, 'uad';
    delete $table{uad};
  }
  if ($table{ct}) {
    push @tableorder, 'ct';
    delete $table{ct};
    $forceback{ct} = 'ua';
  }
  if ($table{cta}) {
    push @tableorder, 'cta';
    delete $table{cta};
  }
  if ($table{a}) {
    push @tableorder, 'a';
    delete $table{a};
  }
  if ($table{j}) {
    push @tableorder, 'j';
    delete $table{j};
  }
  if ($table{b}) {
    push @tableorder, 'b';
    delete $table{b};
  }
  if ($table{bd}) {
    push @tableorder, 'bd';
    delete $table{bd};
  }
  if ($table{ct2}) {
    push @tableorder, 'ct2';
    delete $table{ct2};
    $forceback{ct2} = 'a';
  }
  if ($table{cta2}) {
    push @tableorder, 'cta2';
    delete $table{cta2};
  }
  if ($table{au2}) {
    push @tableorder, 'au2';
    delete $table{au2};
  }
  if ($table{j2}) {
    push @tableorder, 'j2';
    delete $table{j2};
  }
  if ($table{t}) {
    unless (grep($_ eq 'uat', @tableorder)) {
      push @tableorder, 'uat';
      delete $table{uat};
    }
    push @tableorder, 't';
    delete $table{t};
  }
  if ($table{c}) {
    push @tableorder, 'uac', 'c';
    delete $table{uac};
    delete $table{c};
  }
  if ($table{g}) {
    push @tableorder, 'ug', 'g';
    delete $table{ug};
    delete $table{g};
  }
  $table{ua2} = 1 if $table{c2};
  if ($table{ua2}) {
    push @tableorder, 'a2', 'ua2';
    delete $table{a2};
    delete $table{ua2};
  }
  if ($table{c2}) {
    push @tableorder, 'uac2', 'c2';
    delete $table{uac2};
    delete $table{c2};
  }
  if ($table{ua3}) {
    push @tableorder, 'ua3';
    delete $table{ua3};
  }
  if ($table{t3}) {
    push @tableorder, 'uat3', 't3';
    delete $table{uat3};
    delete $table{t3};
  }
  if ($table{t4}) {
    push @tableorder, 'uat4', 't4';
    delete $table{uat4};
    delete $table{t4};
    $forceback{uat4} = 'ua';
  }
  if ($table{t5}) {
    push @tableorder, 'uat5', 't5';
    delete $table{uat5};
    delete $table{t5};
    $forceback{uat5} = 'ua';
  }
  push @tableorder, keys %table;

  my @joins;

  my $find_matching_keys = sub {
    my ($joining_class, $joining_instance_alias, $previous_class, $previous_instance_alias) = @_;
    my %has_a = %{$previous_class->meta_info('has_a') || {}};
    my %has_many = %{$previous_class->meta_info('has_many') || {}};
    my %might_have = %{$previous_class->meta_info('might_have') || {}};
    my %previous_class_relationships = (%might_have, %has_many, %has_a);
    foreach my $meta (keys %has_a, keys %has_many, keys %might_have) {
      if ($previous_class_relationships{$meta}->foreign_class eq $joining_class) {
	# yay, found a way to join $joining_class
	my $previous_class_key = ($previous_class_relationships{$meta}->name ne 'has_a'
				  ? $previous_class->primary_column
				  : $previous_class_relationships{$meta}->accessor);
	my $joining_class_key = $previous_class_relationships{$meta}->args->{foreign_key} || $joining_class->primary_column;
	return ($previous_class_key, $joining_class_key);
      }
    }
    return ();
  };
  my $make_left_join = sub {
    my ($joining_class, $joining_instance_alias, $previous_class, $previous_instance_alias,
	$previous_class_key, $joining_class_key) = @_;
    my $joining_table = eval { return $joining_class->table.' '.$joining_instance_alias; };
    die _debug_pure_dump({options => \%options, error => $@}) if $@;
    #die "($joining_class,$joining_instance_alias,$previous_class,$previous_instance_alias,$previous_class_key,$joining_class_key) $@" if $@;
    return $joining_table unless $previous_class and $previous_instance_alias;
    unless ($previous_class_key) {
      ($previous_class_key, $joining_class_key) = $find_matching_keys->($joining_class,
									$joining_instance_alias,
									$previous_class,
									$previous_instance_alias);
    }
    my $special_option = 'join_'.$joining_instance_alias;
    my $special = $options{$special_option} ? ' AND '.$options{$special_option} : '';
    my $sql = "LEFT JOIN $joining_table ON ($previous_instance_alias.$previous_class_key=$joining_instance_alias.$joining_class_key$special)";
    my $bind_option = 'bind_'.$joining_instance_alias;
    my @bind;
    @bind = @{$options{$bind_option}} if $options{$bind_option};
    return ($sql, \@bind);
  };
  my $make_from = sub {
    my ($tableorder_ref, $forceback_ref, $joins_ref) = @_;
    die 'no tableorder' unless $tableorder_ref;
    my @tableorder = grep($_ ne '*', @{$tableorder_ref});
    $forceback_ref ||= {};
    my @joins = @{$joins_ref || []};
  CLASS:
    foreach my $i_alias (@tableorder) {
      (my $alias = $i_alias) =~ s/\d*(_s)?$//;
      my $class = $class{$alias} or die "class for alias \'$alias\' unknown";
      my $forceback = $forceback_ref->{$i_alias};
      foreach my $predecessor (reverse @joins) {
	my ($p_special_text, $p_special_bind, $p_class, $p_alias) = @{$predecessor};
	next if !$p_class or $class eq $p_class;
	next if $forceback and $p_alias ne $forceback;
	my ($p_key, $key) = $find_matching_keys->($class, $i_alias, $p_class, $p_alias);
	if ($p_key) {
	  push @joins, [undef, undef, $class, $i_alias, $p_class, $p_alias, $p_key, $key];
	  next CLASS;
	}
      }
    }
    my @bind;
    my $from = eval {
      join("\n",
	   map { my $part = 
		     eval { my ($special_text, $special_bind, $class, $i_alias, $p_class, $p_alias, $p_key, $key) = @{$_};
			    if ($special_text) {
			      push @bind, @{$special_bind} if $special_bind;
			      return $special_text;
			    }
			    my ($sql, $bind) = $make_left_join->($class, $i_alias, $p_class, $p_alias, $p_key, $key);
			    push @bind, @{$bind} if $bind;
			    return $sql;
			  };
		 die $@ if $@;
		 $part;
	       } @joins);
    };
    die "$@\n".Dumper(\@joins) if $@;
    return ($from, \@bind);
  };

  if ($options{class} eq 'Bibliotech::User_Article') {

    my $start = $tableorder[0];
    my $start_uap = $start eq 'uap';
    my @subselect_tableorder = $start_uap ? ('ua') : @{$to_ua{$start}};
    if ($start_uap or $options{count} or $group_by =~ /\bb\./) {
      push @subselect_tableorder, 'b' unless $start eq 'b';
    }
    my $subselect_limit = $limit;
    $limit = '';  # do not allow it to be used again on outer query or paging will not work

    my $subselect_sort;
    {
      my $sort = eval { return undef unless $options{select} && @{$options{select}};
			return undef unless $options{select}->[-1] =~ /\bsortvalue\b/;
			return $options{select}->[-1]; };
      $sort =~ s/ [Aa][Ss] sortvalue//;
      if ($sort =~ /\bua\./) {  # if sort is based on user_article...
	# transfer sort to subselect and reference it in the outer sort
	$subselect_sort = $sort;
	my @select = ref $options{select} ? @{$options{select}} : ();
	pop @select;
	$select =~ /([^,+]+) [Aa][Ss] sortvalue/;
	$select = join(', ', @select, $1);
      }
      else {
	$subselect_sort = 'UNIX_TIMESTAMP(MAX(ua.created))';  # default for subselect
      }
    }

    my $select_id = 'ua.user_article_id';
    $select_id = "MAX($select_id)" if $start_uap;

    my $subselect_where = $where;
    $where = 'ua.user_article_id IS NOT NULL';  # previous value already added in query ... this IS NOT NULL part is for privacy
    my @subselect_where_bind = @where_bind;
    @where_bind = ();

    if ($start_uap) {
      $subselect_where = join(' AND ', $subselect_where ? ($subselect_where) : (), $options{join_ua}) if $options{join_ua};
      push @subselect_where_bind, @{$options{bind_ua}} if $options{bind_ua};
    }

    my $subselect_having = $having;
    $having = '';
    my @subselect_having_bind = @having_bind;
    @having_bind = ();

    my $temp_joins = [[undef, undef, $start_uap ? ($class{ua}, 'ua') : ($class{$start}, $start)]];
    my ($subselect_from, $subselect_from_bind) =
	$make_from->(\@subselect_tableorder, \%forceback,
		     $temp_joins);
    my @subselect_from_bind = $subselect_from_bind ? @{$subselect_from_bind} : ();

    if ($options{freematch} and @{$options{freematch}}) {
      my ($freematch_sql, $freematch_bind) = $self->freematch_all_terms(@{$options{freematch}});
      $subselect_from .= "\nINNER JOIN ($freematch_sql) as fm ON (ua.user_article_id=fm.user_article_id)\n";
      push @subselect_from_bind, @{$freematch_bind} if $freematch_bind;
      $subselect_sort = 'fm.sortvalue';
    }

    my $subselect_sql = "\n(".
	join("\n",
	     "SELECT $select_id as max_user_article_id, $subselect_sort as sortvalue",
	     "FROM $subselect_from",
	     $subselect_where ? "WHERE $subselect_where" : '',
	     $options{count} ? 'GROUP BY b.article' : $group_by,
	     $subselect_having,
	     $order_by,
	     $subselect_limit).
	     ") as uap\n";
    my @subselect_bind = (@subselect_from_bind,
			  @subselect_where_bind,
			  @subselect_having_bind);

    @tableorder = grep(!/^(uap|ua|uat)$/, @tableorder);
    $forceback{u} = 'ua';
    $forceback{b} = 'ua';
    push @joins, [$subselect_sql, \@subselect_bind, 'Bibliotech::User_Article', 'uap'];
    push @joins, ['LEFT JOIN user_article ua ON (uap.max_user_article_id=ua.user_article_id)', undef, 'Bibliotech::User_Article', 'ua'];

    # cleanup
    $select =~ s|MAX\(ua.user_article_id\)|ua.user_article_id|;
    $group_by = $options{count} ? '' : 'GROUP BY uap.max_user_article_id';
    my $sortdir = 'ASC';
    $sortdir = $1 if $order_by =~ / (ASC|DESC)$/i;
    $order_by = "ORDER BY sortvalue $sortdir";
  }
  else {
    # entities other than user_article:

    if ($options{freematch} and @{$options{freematch}}) {
      my ($freematch_sql, $freematch_bind) = $self->freematch_all_terms(@{$options{freematch}});
      if ($options{class} eq 'Bibliotech::Bookmark') {
	push @joins, ["($freematch_sql ORDER BY sortvalue) as fm", [@{$freematch_bind||[]}], 'Bibliotech::User_Article', 'fm'];
	push @joins, ['LEFT JOIN user_article uaj ON (fm.user_article_id=uaj.user_article_id)', undef, 'Bibliotech::User_Article', 'uaj'];
	push @joins, ['LEFT JOIN bookmark b ON (uaj.bookmark=b.bookmark_id)', undef, 'Bibliotech::Bookmark', 'b'];
	shift @tableorder if $tableorder[0] eq 'b';
      }
      else {
	die "Currently no support for search on entities other than posts or bookmarks.\n";
      }
    }
    elsif ($options{class} eq 'Bibliotech::Bookmark') {
      my $privacy = $options{join_ua};
      $privacy =~ s/\bua\b/uai/g;
      my $subselect_sql = "\n(".
	  join("\n",
	       "SELECT bi.bookmark_id, (SELECT COUNT(uai.user_article_id) FROM article ai LEFT JOIN user_article uai ON (ai.article_id = uai.article) WHERE bi.article = ai.article_id AND $privacy) AS cnt",
	       'FROM bookmark bi',
	       'HAVING cnt > 0',
	       'ORDER BY bi.created DESC',  # sortvalue should be used here
	       $limit).
	       ") as bic\n";
      $limit = '';
      my @subselect_bind = ($options{bind_ua} ? @{$options{bind_ua}} : ());
      push @joins, [$subselect_sql, \@subselect_bind, 'Bibliotech::Bookmark', 'bic'];
      push @joins, ['LEFT JOIN bookmark b ON (bic.bookmark_id=b.bookmark_id)', undef, 'Bibliotech::Bookmark', 'b'];
      @tableorder = grep(!/^b$/, @tableorder);
      $forceback{a} = 'b';
    }
    else {
      push @joins, [undef, undef, $class{$tableorder[0]}, $tableorder[0]];
      shift @tableorder;

      # add protective clause to avoid NULL user_article_id's when ua is joined with privacy
      # usually when starting with a tag
      if (grep { $_ eq 'ua' } @tableorder[1..$#tableorder]) {
	$where .= ' AND ua.user_article_id IS NOT NULL';  # this IS NOT NULL part is for privacy
      }
    }
  }

  my ($from, $from_bind) = $make_from->(\@tableorder, \%forceback, \@joins);
  my @from_bind = $from_bind ? @{$from_bind} : ();

  my $firstalias = $joins[0]->[3];
  my $special_option = 'join_'.$firstalias;
  if ($options{$special_option}) {
    $where .= ' AND ' if $where;
    $where .= $options{$special_option};
    my $bind_option = 'bind_'.$firstalias;
    unshift @from_bind, @{$options{$bind_option}} if $options{$bind_option};
  }
  if ($where) {
    $where =~ s/^\s*AND\s*//;
    $where = "WHERE $where";
  }
  my $sql = join("\n",
		 "SELECT $select",
		 "FROM $from",
		 grep($_,
		      $where,
		      $group_by,
		      $having,
		      $order_by,
		      $limit));
  my @bind = (@select_bind,
	      @from_bind,
	      @where_bind,
	      @having_bind);
  return ($sql, \@bind);
}

sub packed_or_raw {
  my ($self, $packed_class, $packed_func, $raw_func) = @_;
  if (defined(my $packed = $self->$packed_func)) {
    return () if $packed eq '';
    return @{$packed} if ref $packed eq 'ARRAY';
    my @obj;
    my @essential = $packed_class->_essential;
    foreach (split(/\/\/\//, $packed)) {
      my @data = map { $_ = undef if $_ eq '+NULL'; $_; } split(/:\/:/);
      my %hash;
      @hash{@essential} = @data;
      push @obj, $packed_class->construct(\%hash);
    }
    $self->$packed_func(\@obj);
    return @obj;
  }
  return $raw_func ? $self->$raw_func : ();
}

__PACKAGE__->set_sql(joined => <<'');
SELECT 	 %s
FROM     __TABLE(Bibliotech::User_Article=ua)__,
   	 __TABLE(Bibliotech::Article=a)__,
   	 __TABLE(Bibliotech::User=u)__
WHERE  	 __JOIN(ua a)__
AND    	 __JOIN(ua u)__
%s
%s
%s
%s
%s

__PACKAGE__->set_sql(joined_plus_details => <<'');
SELECT 	 %s
FROM     __TABLE(Bibliotech::User_Article=ua)__,
   	 __TABLE(Bibliotech::User_Article_Details=uad)__,
   	 __TABLE(Bibliotech::Article=a)__,
   	 __TABLE(Bibliotech::User=u)__
WHERE  	 __JOIN(ua a)__
AND    	 __JOIN(ua u)__
%s
%s
%s
%s
%s

__PACKAGE__->set_sql(joined_plus_tag => <<'');
SELECT 	 %s
FROM     __TABLE(Bibliotech::Tag=t)__,
       	 __TABLE(Bibliotech::User_Article_Tag=uat)__,
       	 __TABLE(Bibliotech::User_Article=ua)__,
   	 __TABLE(Bibliotech::Article=a)__,
   	 __TABLE(Bibliotech::User=u)__
WHERE  	 __JOIN(t uat)__
AND    	 __JOIN(uat ua)__
AND    	 __JOIN(ua a)__
AND    	 __JOIN(ua u)__
%s
%s
%s
%s
%s

__PACKAGE__->set_sql(joined_related_user => <<'');
SELECT 	 %s
FROM     __TABLE(Bibliotech::User_Article=ua)__,
   	 __TABLE(Bibliotech::Article=a)__,
   	 __TABLE(Bibliotech::User=u)__,
         __TABLE(Bibliotech::User_Article=ua2)__,
   	 __TABLE(Bibliotech::User=r)__
WHERE  	 __JOIN(ua a)__
AND    	 __JOIN(ua u)__
AND    	 __JOIN(a ua2)__
AND    	 __JOIN(ua2 r)__
%s
%s
%s
%s
%s

__PACKAGE__->set_sql(joined_plus_tag_related_tag => <<'');
SELECT 	 %s
FROM     __TABLE(Bibliotech::Tag=t)__,
       	 __TABLE(Bibliotech::User_Article_Tag=uat)__,
       	 __TABLE(Bibliotech::User_Article=ua)__,
   	 __TABLE(Bibliotech::Article=a)__,
   	 __TABLE(Bibliotech::User=u)__,
       	 __TABLE(Bibliotech::User_Article=ua2)__,
       	 __TABLE(Bibliotech::User_Article_Tag=uat2)__,
         __TABLE(Bibliotech::Tag=r)__
WHERE  	 __JOIN(t uat2)__
AND    	 __JOIN(uat ua)__
AND    	 __JOIN(ua a)__
AND    	 __JOIN(ua u)__
AND    	 __JOIN(a ua2)__
AND    	 __JOIN(ua2 uat2)__
AND    	 __JOIN(uat2 r)__
%s
%s
%s
%s
%s

__PACKAGE__->set_sql(joined_plus_gang => <<'');
SELECT 	 %s
FROM     __TABLE(Bibliotech::User_Article=ua)__,
   	 __TABLE(Bibliotech::Article=a)__,
   	 __TABLE(Bibliotech::User=u)__,
   	 __TABLE(Bibliotech::User_Gang=ug)__,
   	 __TABLE(Bibliotech::Gang=g)__
WHERE  	 __JOIN(ua a)__
AND    	 __JOIN(ua u)__
AND    	 __JOIN(u ug)__
AND    	 __JOIN(ug g)__
%s
%s
%s
%s
%s

__PACKAGE__->set_sql(joined_plus_tag_plus_gang => <<'');
SELECT 	 %s
FROM     __TABLE(Bibliotech::Tag=t)__,
       	 __TABLE(Bibliotech::User_Article_Tag=uat)__,
       	 __TABLE(Bibliotech::User_Article=ua)__,
   	 __TABLE(Bibliotech::Article=a)__,
   	 __TABLE(Bibliotech::User=u)__,
   	 __TABLE(Bibliotech::User_Gang=ug)__,
   	 __TABLE(Bibliotech::Gang=g)__
WHERE  	 __JOIN(t uat)__
AND    	 __JOIN(uat ua)__
AND    	 __JOIN(ua a)__
AND    	 __JOIN(ua u)__
AND    	 __JOIN(u ug)__
AND    	 __JOIN(ug g)__
%s
%s
%s
%s
%s

__PACKAGE__->set_sql(retrieve_ordered => <<'');
SELECT __ESSENTIAL__
FROM   __TABLE__
ORDER BY %s

 __PACKAGE__->set_sql(last_updated => <<'');
SELECT MAX(created)
FROM   __TABLE__

sub db_last_updated_slow_method {
  my $sth = shift->sql_joined(join(', ',
				   'UNIX_TIMESTAMP(MAX(u.last_deletion))',
				   map("UNIX_TIMESTAMP(MAX($_.created))", qw/b u t ua uat/),
				   map("UNIX_TIMESTAMP(MAX($_.updated))", qw/u ua/)),
			      '', '', '', '', '');
  $sth->execute;
  my $highest = 0;
  foreach ($sth->fetch) {
    $highest = $_ if $_ > $highest;
  }
  $sth->finish;
  return $highest;
}

sub db_get_last_updated {
  my $time = $Bibliotech::Apache::QUICK{DB} || $Bibliotech::Apache::MEMCACHE->get('DB');
  return $time if defined $time;
  return db_set_last_updated();
}

sub db_set_last_updated {
  my $time = Bibliotech::Util::time();
  $Bibliotech::Apache::QUICK{DB} = $time;
  $Bibliotech::Apache::MEMCACHE->set(DB => $time, 1296000) if $Bibliotech::Apache::MEMCACHE;  # 15 day timout
  return $time;
}

foreach (qw/create update delete/) {
  __PACKAGE__->add_trigger('after_'.$_ => \&db_set_last_updated);
}

sub retrieve_ordered {
  my $self = shift;
  $self->_sth_to_objects($self->sql_retrieve_ordered(@_));
}

sub label {
  my ($self) = @_;
  my $unique = $self->unique or return undef;
  return $self->$unique;
}

# used for RSS description - gives a more human readable, personalized label than label()
sub label_title { shift->label(@_); }

# used for command descriptions (see Bibliotech::Command)
sub label_short {
  my $self = shift;
  my $label = $self->label(@_);
  $label =~ s|^(.{50}).+$|$1...|;
  return $label;
}

# used to make wiki page names from label, etc.
# get hash for article instead of url, etc
sub label_parse_easy {
  shift->label(@_);
}

# used for tag names in javascript mostly
sub label_with_single_quotes_escaped {
  my $self = shift;
  my $label = $self->label_parse_easy(@_);
  $label =~ s/\'/\\\'/g;
  return $label;
}

sub debug_id {
  my $self = shift;
  return ref($self) . '(' . $self->label . ':' . $self->get($self->primary_column) . ')';
}

sub search_key { shift->table; }
sub search_value { shift->label(@_); }

sub filter_name_to_label {
  my $name = pop;
  foreach (@FILTERS) {
    return $_->{label} if $name eq $_->{name};
  }
  return undef;
}

sub href_with_extras {
  my ($self, $bibliotech, $uri, $extras_ref) = @_;
  return $bibliotech->location.
      ($extras_ref && %{$extras_ref} ? join('/', map($_.'/'.$extras_ref->{$_}, keys %{$extras_ref})).'/' : '').
      $uri;
}

# for the main objects; this will replace the query uri with a new key+value
sub href_search_global {
  my ($self, $bibliotech, $extras_ref) = @_;
  die 'no bibliotech object' unless $bibliotech;
  my $key   = filter_name_to_label($self->search_key);
  my $value = $self->search_value;
  my $uri   = join('/', $key, $value);
  return $self->href_with_extras($bibliotech, $uri, $extras_ref);
}

sub href_search_global_user {
  my ($self, $bibliotech) = @_;
  my %user;
  $user{user} = $Bibliotech::Apache::USER->username if defined $Bibliotech::Apache::USER;
  return $self->href_search_global($bibliotech, \%user);
}

# for the main objects; this will analyze and supplement the query uri with an extra key+value
sub href_search_additive {
  my ($self, $bibliotech) = @_;
  die 'no bibliotech object' unless $bibliotech;
  return $bibliotech->command->canonical_uri($bibliotech->location,
					     {$self->search_key => [add => $self->search_value],
					      freematch => [set => undef]});
}

# for the main objects; this will analyze and supplement the query uri with an extra key+value but remove similar keys
sub href_search_replacitive {
  my ($self, $bibliotech) = @_;
  die 'no bibliotech object' unless $bibliotech;
  return $bibliotech->command->canonical_uri($bibliotech->location,
					     {$self->search_key => [replace => $self->search_value],
					      freematch => [set => undef]});
}

# for the main objects; this will analyze and supplement the query uri with an extra key+value
sub href_search_additive_and {
  my ($self, $bibliotech) = @_;
  die 'no bibliotech object' unless $bibliotech;
  my $search_key = $self->search_key;
  my $search_value = $self->search_value;
  my $command = $bibliotech->command;
  my $existing_criteria = $command->$search_key;
  my @new_criteria = map { [map("$_", (ref $_ eq 'ARRAY' ? @{$_} : $_)), $search_value] } @{$existing_criteria};
  push @new_criteria, $search_value unless @new_criteria;
  return $bibliotech->command->canonical_uri($bibliotech->location,
					     {$search_key => [replace => @new_criteria],
					      freematch => [set => undef]});
}

sub href { shift->href_search_additive(@_); }

sub link_generic {
  my ($self, $href, $label, $cgi, $class, $title, $onclick) = @_;
  my %options;
  $options{href}    = $href    if $href;
  $options{class}   = $class   if $class;
  $options{title}   = $title   if $title;
  $options{onclick} = $onclick if $onclick;
  my $func = $href ? 'a' : 'span';
  return $cgi->$func(\%options, Bibliotech::Util::encode_xhtml_utf8($label));
}

sub link {
  my ($self, $bibliotech, $class, $href_func, $label_func, $verbose, $onclick) = @_;
  $href_func  ||= 'href';
  $label_func ||= 'label';
  my $full_label = $self->$label_func || '(no label)';
  my $label = $full_label;
  unless ($verbose) {
    $label =~ s/(\S{10}_)(\S)/$1- $2/g;  # add space after underscore following longish word
    $label =~ s/(\S{20})(\S)/$1- $2/g;   # then, if still necessary, break up large "words"
  }
  #$label =~ s|^(.{20}).+$|$1...| unless $verbose;
  return $self->link_generic($self->$href_func($bibliotech),
			     $label,
			     $bibliotech->cgi,
			     $class,
			     $full_label,
			     $onclick);
}

sub visit_link {
  my ($self, $bibliotech, $class) = @_;
  return $bibliotech->cgi->div({class => ($class || 'referent')},
			       'Visit the ',
			       $bibliotech->sitename,
			       'page for the',
			       $self->noun,
			       $self->link($bibliotech, undef, 'href_search_global', undef, 1).'.'
			       );
}

sub plain_content {
  my ($self, $verbose) = @_;
  my @output = ($self->label);
  push @output, $self->created if $verbose;
  return @output if wantarray;
  return $output[0] if @output == 1;
  return sprintf('%-60s (%s)', $output[0], join(' ', @output[1..$#output]));
}

sub txt_content {
  my ($self, $bibliotech, $verbose) = @_;
  return $self->plain_content($verbose);
}

sub ris_content {
  my ($self, $bibliotech, $verbose) = @_;
  return {TY => 'ELEC',
	  TI => $self->label,
	  UR => $self->href_search_global($bibliotech),
	 };
}

sub html_content {
  my ($self, $bibliotech, $class, $verbose, $main, $href_type) = @_;
  $href_type ||= 'href_search_global' if $main;

  my $cgi = $bibliotech->cgi;

  my $link = $self->link($bibliotech, $class, $href_type, undef, $verbose);
  my @output = ($link);

  if ($verbose) {
    if ($self->can('description')) {
      if (my $description = $self->description) {
	push @output, $cgi->span({class => 'description'},
				 Bibliotech::Util::encode_markup_xhtml_utf8($description));
      }
    }
    push @output, 'Created '.$self->created->link($bibliotech, undef, $href_type, undef, $verbose);
  }

  return wantarray ? @output : join($cgi->br, @output);
}

sub rss_content {
  my ($self, $bibliotech, $verbose) = @_;

  my %item = (title 	  => $self->label,
	      link  	  => href_search_global($self, $bibliotech),
	      description => $self->label_title);

  if ($verbose) {
    my $date = do { if ($self->can('rss_date_override') and my $override = $self->rss_date_override) {
                      Bibliotech::Date->new($override);
		    }
		    else {
		      $self->created;
		    }
		  };
    $item{dc} = {date => $date->iso8601_utc};
    $item{dc}->{subject} = [map($_->label, $self->tags)] if $self->can('tags');
  }

  return wantarray ? %item : \%item;
}

sub collective_name_part {
  my $self = shift;
  my @names;
  foreach (@_) {
    if (ref $_) {
      my @inset = $self->collective_name_part(@{$_});
      push @names, $inset[0] if @inset;
    }
    else {
      if (/^!/) {
	last if @names;
      }
      elsif (/^\+(.+)$/) {
	$names[$#names] .= $1 if @names;
      }
      elsif ($self->can($_)) {
	if (my $value = $self->$_) {
	  $value =~ s/^\s*(.+)\s*$/$1/;  # remove superfluous spacing
	  push @names, $value;
	}
      }
    }
  }
  return @names;
}

sub collective_name {
  my ($self, $reverse) = @_;
  my @candidates;
  if ($reverse) {
    @candidates = ('misc', '!', 'lastname', '+,', 'suffix', ['forename', 'firstname', 'initials']);
  }
  else {
    @candidates = ('misc', '!', 'prefix', ['forename', 'firstname', 'initials'], 'lastname', 'suffix');
  }
  return join(' ', $self->collective_name_part(@candidates));
}

sub clean_whitespace {
  my ($self, $field) = @_;
  die 'no field specified' unless $field;
  if (defined (my $value = $self->$field)) {
    if (ref $value) {
      if (UNIVERSAL::can($value, 'clean_whitespace_all')) {
	$value->clean_whitespace_all;
      }
      else {
	die "cannot clean whitespace for $field";
      }
    }
    else {
      my $original = $value;
      $value = Bibliotech::Util::clean_whitespace($value);
      $self->$field($value) if $value ne $original;
    }
  }
}

# will be overridden to give an alias for some SQL operations
# had problems using the Class::DBI official table_alias property (bugs in Class::DBI)
sub my_alias {
  shift->table;
}

# convert 'user' to 'Bibliotech::User' etc.
sub class_for_table {
  shift if $_[0] eq __PACKAGE__;
  my $table = shift;
  $table =~ s/\b([a-z])/uc($1)/ge;
  return 'Bibliotech::'.$table;
}

# convert 'group' to 'Bibliotech::Gang' etc.
sub class_for_name {
  shift if $_[0] eq __PACKAGE__;
  my $name = shift;
  $name =~ s/\b([a-z])/uc($1)/ge;
  $name =~ s/Group/Gang/;
  return 'Bibliotech::'.$name;
}

__PACKAGE__->set_sql(single => <<"");
SELECT %s
FROM   ${DBI_SEARCH_DOT_OR_BLANK}__TABLE__

# untaint the parameter because usually it's going into a database query without quotes
sub untaint_time_window_spec {
  my $spec = pop || '30 DAY';
  $spec =~ /^(\d+) (SECOND|MINUTE|HOUR|DAY|WEEK|MONTH|QUARTER|YEAR)S?$/i
      or die 'window parameter should be a number followed by time spec like HOUR or DAY';
  return int($1).' '.uc($2);
}

# untaint the parameter because usually it's going into a database query without quotes
sub untaint_limit_spec {
  my $spec = pop;
  $spec =~ /^(\d+)$/
      or die 'limit parameter should be a number';
  return int($1);
}

sub json_content {
  my $self = shift;
  return {%{$self}};
}


# The following classes either all need to be in this file, or we at
# least need to establish their superclass as the above class:

# http://rt.cpan.org/Public/Bug/Display.html?id=3305

package Bibliotech::User;
use base 'Bibliotech::DBI';
package Bibliotech::Gang;
use base 'Bibliotech::DBI';
package Bibliotech::User_Gang;
use base 'Bibliotech::DBI';
package Biblitech::Bookmark;
use base 'Bibliotech::DBI';
package Bibliotech::Tag;
use base 'Bibliotech::DBI';
package Bibliotech::User_Tag_Annotation;
use base 'Bibliotech::DBI';
package Bibliotech::Article;
use base 'Bibliotech::DBI';
package Bibliotech::User_Article;
use base 'Bibliotech::DBI';
package Bibliotech::User_Article_Tag;
use base 'Bibliotech::DBI';
package Bibliotech::User_Article_Details;
use base 'Bibliotech::DBI';
package Bibliotech::User_Article_Comment;
use base 'Bibliotech::DBI';
package Bibliotech::Comment;
use base 'Bibliotech::DBI';
package Bibliotech::Bookmark_Details;
use base 'Bibliotech::DBI';
package Bibliotech::Citation;
use base 'Bibliotech::DBI';
package Bibliotech::Author;
use base 'Bibliotech::DBI';
package Bibliotech::Citation_Author;
use base 'Bibliotech::DBI';
package Bibliotech::Journal;
use base 'Bibliotech::DBI';
package Bibliotech::Date;
use base 'Bibliotech::DBI';

1;
__END__
