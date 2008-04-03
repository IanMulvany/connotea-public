# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Parser class interprets the text of each query and converts
# it to a Bibliotech::Command object.

package Bibliotech::Parser;
use strict;
use utf8;
use Parse::RecDescent;
use Bibliotech::DBI;
use Bibliotech::Command;
use Encode qw/is_utf8 decode_utf8 encode_utf8 _utf8_on/;
use CGI ();

our $RESERVED_PREFIXES = Bibliotech::Config->get('RESERVED_PREFIXES');
our $SKIP_VALIDATE = 0;

my $grammar = <<'EOG';

auth : 'auth'

# not really <reject>, set by code in Parser.pm
output : <reject>

page : 'library/export' | 'library' | 'profile'
     | 'recent' | 'populartags' | 'popular'
     | 'loginpopup' | 'login' | 'logout'
     | 'openid'
     | 'commentspopup' | 'comments'
     | 'addcommentpopup' | 'addcomment'
     | 'addgroup' | 'editgroup'
     | 'addtagnote' | 'edittagnote'
     | 'addpopup' | 'editpopup'
     | 'add' | 'edit'
     | 'remove'
     | 'retag'
     | 'upload'
     | 'search'
     | 'error'
     | 'register' | 'verify' | 'advanced'
     | 'bookmarks' | 'users' | 'groups' | 'tags'
     | 'cloud'
     | 'blog'
     | 'forgotpw'
     | 'resendreg'
     | 'reportspam'
     | 'reportproblem'
     | 'home'
     | 'sabotage'
     | 'noop'
     | 'killspammer'
     | 'export/library' | 'export'
     | 'click'
     | 'citation'
     | 'adminstats'
     | 'adminrenameuser'
     | 'admin'
     | filename_part <reject: $item[1] !~ /\.(?:css|js|txt|html)$/> { [none => $item[1]] }
     | filename_part                                                { [inc  => $item[1]] }

# not actually used but just to remind people that there's the wiki too
all_pages : page | 'wiki'

# not necessarily <reject>, optionally set by code in Parser.pm
user_part_banned_prefix : <reject>

# not necessarily <reject>, optionally set by code in Parser.pm
gang_part_banned_prefix : <reject>

user_part : ...!keyword_for_user ...!user_part_banned_prefix /[A-Za-z_]\w{2,39}/

gang_part : ...!keyword_for_gang ...!gang_part_banned_prefix /[A-Za-z_][\w \-]{2,39}/

tag_part_nospace : ...!keyword_for_tag /[^\s,\/\+\"\'\?][^\s,\/\+\"\?]*(?<!\')/

tag_part         : ...!keyword_for_tag /[^\/\+\"\'\?]([^\/\+\"\?](?! \'))*(?<!\')/

user_part_create : /^/ user_part /$/
{ $item[2] }

gang_part_create : /^/ gang_part /$/
{ $item[2] }

tag_part_create  : /^/ tag_part /$/
{ $item[2] }

date_part : ...!keyword_for_date /\d{4}-\d{2}-\d{2}/

bookmark_part : ...!keyword_for_bookmark /[0-9a-f]{32}/ <commit>
                { $item[2] }
              | ...!keyword_for_bookmark /[^\'\" ][^\" ]*/
                { $item[2] }

article_part : ...!keyword_for_article /[0-9a-f]{32}/ <commit>
               { $item[2] }

filename_part : ...!keyword /[\w\.]+/

user_boolAND_part : <skip:'/*'> user_part(2.. /\+/)
{ $item[2] }

tag_boolAND_part : <skip:'/*'> tag_part(2.. /\+/)
{ $item[2] }

date_boolAND_part : <skip:'/*'> date_part(2.. /\+/)
{ $item[2] }

bookmark_boolAND_part : <skip:'/*'> bookmark_part(2.. /\+/)
{ $item[2] }

article_boolAND_part : <skip:'/*'> article_part(2.. /\+/)
{ $item[2] }

user_boolOR_part : user_boolAND_part | user_part
{ $item[1] }

tag_boolOR_part : tag_boolAND_part | tag_part
{ $item[1] }

date_boolOR_part : date_boolAND_part | date_part
{ $item[1] }

bookmark_boolOR_part : bookmark_boolAND_part | bookmark_part
{ $item[1] }

article_boolOR_part : article_boolAND_part | article_part
{ $item[1] }

user_keyword : 'user'

gang_keyword : 'group'

tag_keyword : 'tag'

date_keyword : 'date'

bookmark_keyword : 'uri'

article_keyword : 'article'

raw_keyword : user_keyword | gang_keyword | date_keyword | bookmark_keyword | article | tag_keyword

keyword : raw_keyword <reject: $text =~ /^\w/>
{ $item[1] }

raw_keyword_for_user : gang_keyword | date_keyword | bookmark_keyword | article_keyword | tag_keyword

keyword_for_user : raw_keyword_for_user <reject: $text =~ /^\w/>
{ $item[1] }

raw_keyword_for_gang : date_keyword | bookmark_keyword | article_keyword | tag_keyword

keyword_for_gang : raw_keyword_for_gang <reject: $text =~ /^\w/>
{ $item[1] }

raw_keyword_for_date : bookmark_keyword | article_keyword | tag_keyword

keyword_for_date : raw_keyword_for_date <reject: $text =~ /^\w/>
{ $item[1] }

raw_keyword_for_bookmark : article_keyword | tag_keyword

keyword_for_bookmark : raw_keyword_for_bookmark <reject: $text =~ /^\w/>
{ $item[1] }

keyword_for_article : tag_keyword <reject: $text =~ /^\w/>
{ $item[1] }

keyword_for_tag : <reject>

user : user_keyword <commit> user_boolOR_part(s?)
{ Bibliotech::Parser::validate_part_list('user', 'user', 'Bibliotech::User', $item[3]); }

gang : gang_keyword <commit> gang_part(s?)
{ Bibliotech::Parser::validate_part_list('group', 'gang', 'Bibliotech::Gang', $item[3]); }

tag : tag_keyword <commit> tag_boolOR_part(s?)
{ Bibliotech::Parser::validate_part_list('tag', 'tag', 'Bibliotech::Tag', $item[3]); }

date : date_keyword <commit> date_boolOR_part(s?)
{ Bibliotech::Parser::validate_part_list('date', 'date', 'Bibliotech::Date', $item[3]); }

bookmark : bookmark_keyword <commit> bookmark_boolOR_part(s?)
{ Bibliotech::Parser::validate_part_list('bookmark', 'bookmark', 'Bibliotech::Bookmark', $item[3]); }

article : article_keyword <commit> article_boolOR_part(s?)
{ Bibliotech::Parser::validate_part_list('article', 'article', 'Bibliotech::Article', $item[3]); }

start_keyword : 'start'

num_keyword : 'num'

sort_keyword : 'sort'

freematch_keyword : 'q'

debug_keyword : 'debug'

design_test_keyword : 'designtest'

digit_param : start_keyword
            | num_keyword
            | debug_keyword

digit_arg : digit_param <commit> '=' /\d*/
{ [$item[1] => $item[4]] }

word_param : sort_keyword
           | design_test_keyword

word_arg : word_param <commit> '=' /[\.\w]*/
{ [$item[1] => $item[4]] }

freematch_param : freematch_keyword

freematch_arg : freematch_param <commit> '=' /[^\&\r\n]*/
{ [$item[1] => ($item[4] ? CGI::unescape($item[4]) : undef)] }

other_keyword : /[\w\.]+/

other_arg : other_keyword '=' /[^\&\r\n]*/
{ [$item[1] => ($item[3] ? CGI::unescape($item[3]) : undef)] }

arg : digit_arg
    | word_arg
    | freematch_arg
    | other_arg

modifiers : '?' arg(s /\&/)
{ my @x = map { @{$_} } @{$item[2]}; my %y = @x; \%y; }

query_command : /^/ <skip:'/+'> auth(?) output(?) page(?) user(?) gang(?) date(?) bookmark(?) article(?) tag(?) <skip:'/*'> modifiers(?) /$/
{ Bibliotech::Command->new
      ({verb      => undef,
	output    => $item[4]->[0] || 'html',
	page      => $item[5]->[0] || (!($item[6]->[0] ||
					 $item[7]->[0] ||
					 $item[8]->[0] ||
					 $item[9]->[0] ||
					 $item[10]->[0] ||
				         $item[11]->[0]) ? 'home' : 'recent'),
        user      => $item[6]->[0]  ? bless($item[6]->[0],  'Bibliotech::Parser::NamePartSet') : undef,
	gang      => $item[7]->[0]  ? bless($item[7]->[0],  'Bibliotech::Parser::NamePartSet') : undef,
	date      => $item[8]->[0]  ? bless($item[8]->[0],  'Bibliotech::Parser::NamePartSet') : undef,
	bookmark  => $item[9]->[0]  ? bless($item[9]->[0],  'Bibliotech::Parser::NamePartSet') : undef,
	article   => $item[10]->[0] ? bless($item[10]->[0], 'Bibliotech::Parser::NamePartSet') : undef,
	tag       => $item[11]->[0] ? bless($item[11]->[0], 'Bibliotech::Parser::NamePartSet') : undef,
	start     => $item[13]->[0]->{start} || undef,
	num       => $item[13]->[0]->{num}   || Bibliotech::Parser::num_default($item[4]->[0]),
	sort      => $item[13]->[0]->{sort}  || undef,
	freematch => Bibliotech::Parser::Freematch->new($item[13]->[0]->{'q'}) || undef,
       });
}

wiki_path : /[\w: \-]+/

wiki_command : /^/ <skip:'/+'> auth(?) output(?) 'wiki' <commit> wiki_path(?) <skip:'/*'> modifiers(?) /$/
{ Bibliotech::Command->new
      ({verb      => undef,
	output    => $item[4]->[0] || 'html',
	page      => 'wiki',
	wiki_path => $item[7]->[0],
       });
}

command : wiki_command
        | query_command
{ $item[1] }

tag_list_part : <skip:'\s*'> /[\"\']/ tag_part /$item[2]/
                { $item{tag_part} }
              | tag_part_nospace

tag_list : /^/ tag_list_part(s /,?/) /$/
{ $item[2] }

tag_search_boolAND_part : tag_list_part(2.. / *\+ */)
{ $item[1] }

tag_search_boolOR_part : tag_search_boolAND_part | tag_list_part
{ $item[1] }

tag_search : <skip:''> /^/ tag_search_boolOR_part(s /[\/, ]+/) /$/
{ $item[3] }

EOG

# significant entry points on grammar:
#   command - interpret the incoming URI for Apache handler, call via parse() below
#   tag_list - interpret list of tags for add form, call via tag_list() below
#   tag_search - interpret list of tags for search form, call via tag_search() below

our $PARSER_CACHE = Parse::RecDescent->new($grammar);
if ($RESERVED_PREFIXES and @{$RESERVED_PREFIXES}) {
  my $prd_alternatives = join(' | ', map("\'$_\'", @{$RESERVED_PREFIXES}));
  $PARSER_CACHE->Replace($_.'_part_banned_prefix : '.$prd_alternatives) foreach ('user', 'gang');
}

our @OUTPUTS = qw/html rss ris plain txt data geo tt bib end mods word/;
if (@OUTPUTS) {
  my $prd_alternatives = join(' | ', map("\'$_\'", @OUTPUTS));
  $PARSER_CACHE->Replace('output : '.$prd_alternatives);
}

sub num_default {
  my $output = pop || 'html';
  return   10 if $output eq 'html';
  return   10 if $output eq 'rss';
  return 1000;
}

sub new {
  my $class = shift;
  return bless {PRD => $PARSER_CACHE}, ref $class || $class;
}

sub parse {
  my ($self, $text, $verb) = @_;
  my $command = $self->{PRD}->command($text) or return undef;
  $command->verb($verb);
  return $command;
}

sub check_format {
  my ($self, $part, $value) = @_;
  my $rule = $part.'_part_create';
  return $self->{PRD}->$rule($value) ? 1 : 0;
}

sub check_user_format {
  my ($self, $username) = @_;
  return $self->check_format(user => $username);
}

sub check_gang_format {
  my ($self, $gangname) = @_;
  return $self->check_format(gang => $gangname);
}

sub check_tag_format {
  my ($self, $tagname) = @_;
  return $self->check_format(tag => $tagname);
}

sub check_gangname_format {
  my ($self, $gangname) = @_;
  return $self->{PRD}->gang_part($gangname) ? 1 : 0;
}

sub validate_part {
  my ($keyword, $type, $class, $part) = @_;
  my $obj = $class->new($part);
  die "Sorry, $part is not a recognized $keyword.\n" unless defined $obj and ref $obj eq $class;  # incomplete date will come back as different class
  if ($obj->can('private')) {
    if ($obj->private) {
      if (defined(my $user = $Bibliotech::Apache::USER)) {
	die $obj->access_message."\n" unless $obj->is_accessible_by_user($user);
      }
      else {
	die $obj->access_message." You are currently not logged in.\n";
      }
    }
  }
  return Bibliotech::Parser::NamePart->new($part => $obj);
}

sub validate_part_list {
  my $keyword = shift;
  my $type = shift;
  my $class = shift;
  my @ret;
  die "Query is missing a parameter after the keyword \"$keyword\".\n" if !@_ or !defined($_[0]);
  if (!$SKIP_VALIDATE and ($class eq 'Bibliotech::User' or $class eq 'Bibliotech::Gang' or $class eq 'Bibliotech::Date')) {
    foreach (@_) {
      if (ref($_) eq 'ARRAY') {
	push @ret, [validate_part_list($keyword, $type, $class, @{$_})];
      }
      else {
	push @ret, validate_part($keyword, $type, $class, $_);
      }
    }
  }
  else {
    foreach (@_) {
      if (ref($_) eq 'ARRAY') {
	push @ret, [validate_part_list($keyword, $type, $class, @{$_})];
      }
      else {
	push @ret, Bibliotech::Parser::NamePart->new($_ => $class);
      }
    }
  }
  return @ret == 1 ? $ret[0] : @ret;
}

sub tag_list {
  my ($self, $text, $rule) = @_;
  $rule ||= 'tag_list';
  my $temp = $text;
  $temp = decode_utf8($temp) || encode_utf8(decode_utf8($temp)) || $temp unless is_utf8($temp);
  $temp =~ s/\p{IsComma}/,/g;                        # we define IsComma below
  $temp =~ s/\p{Zs}/ /g;                             # \s would probably be fine here too due to 'use utf8'
  $temp =~ s/\p{IsQuote}/\"/g;                       # Quotation_Mark would have included Po apostophes
  $temp =~ s/([^[:ascii:]])/'->c'.ord($1).'c<-'/ge;  # Parse::RecDescent cannot handle utf8 so quote it
  my $value = encode_utf8($temp);                    # remove the Perl utf8 flag
  my $tags_ref = $self->{PRD}->$rule($value) || [];
  $self->tag_list_fix($tags_ref);
  return wantarray ? @{$tags_ref} : $tags_ref;
}

sub tag_list_fix {
  my ($self, $array_ref) = @_;
  foreach (0 .. $#{$array_ref}) {
    if (ref $array_ref->[$_]) {
      $self->tag_list_fix($array_ref->[$_]);
    }
    else {
      _utf8_on($array_ref->[$_]);
      $array_ref->[$_] =~ s/->c(\d+)c<-/chr($1)/ge;
    }
  }
}

sub want_single_tag_but_may_have_more {
  my ($self, $text) = @_;
  my @tags = $self->tag_list($text);
  return undef if @tags == 0;
  my $candidate;
  if (@tags == 1) {
    $candidate = $tags[0];
  }
  else {
    $candidate = join(' ', @tags);
  }
  my $namepart;
  eval {
    $namepart = validate_part('tag', 'tag', 'Bibliotech::Tag', $candidate);
  };
  die $@ if $@ =~ / at .* line /;  # ignore all $@ errors except Perl errors
  return $namepart->obj if defined $namepart;
  if (@tags == 1) {
    die "This tag name was not found; please check that you have entered it correctly.\n";
  }
  else {
    die "Only a single tag name may be provided.\n";
  }
}

sub tag_search {
  my ($self, $text) = @_;
  return $self->tag_list($text, 'tag_search');
}

# Unicode supplements

# http://www.unicode.org/Public/UNIDATA/PropList.txt
# Terminal_Punctuation
# just the COMMA's
sub IsComma {
  return <<'END';
002C
060C
1802
1808
3001
FE50
FF0C
FF64
END
}

# http://www.unicode.org/Public/UNIDATA/PropList.txt
# Quotation_Mark
# all except APOSTROPHE's
sub IsQuote {
  return <<'END';
00AB
00BB
2018
2019
201A
201B
201C
201D
201E
201F
2039
203A
300C
300D
300E
300F
301D
301E
301F
FE41
FE42
FE43
FE44
FF02
FF07
FF62
FF63
END
}

package Bibliotech::Parser::NamePart;
use strict;

use overload
    '""' => sub { shift->stringify_self; },
    fallback => 1;

sub new {
  my ($proto, $name, $class_or_obj) = @_;
  my ($class, $obj);
  if ($class = ref($class_or_obj)) {
    $obj = $class_or_obj;
  }
  else {
    $class = $class_or_obj;
  }
  return bless [$name, $class, $obj], ref $proto || $proto;
}

sub stringify_self {
  my $self = shift;
  return overload::StrVal($self) if caller(1) =~ /^(Data|Devel)::/;  # react normally to Perl introspective modules
  my ($name, $class, $obj) = @{$self};
  return $name || "$obj" || $class;
}

sub name {
  my $self = shift;
  my ($name, $class, $obj) = @{$self};
  return $name if defined $name;
  return $obj->label if defined $obj;
  return undef;
}

sub class {
  my $self = shift;
  my ($name, $class, $obj) = @{$self};
  return $class if $class;
  return ref($obj);
}

sub obj {
  my $self = shift;
  my ($name, $class, $obj) = @{$self};
  return $obj if defined $obj;
  if ($class and $name) {
    my $ret;
    eval {
      $ret = $class->new($name);
    };
    die "cannot call new $class ($name): $@" if $@;
    return $ret;
  }
  return undef;
}

sub obj_id_or_zero {
  my $obj = shift->obj;
  return defined $obj ? $obj->id : 0;
}

package Bibliotech::Parser::NamePartSet;
use base 'Bibliotech::DBI::Set';

package Bibliotech::Parser::Freematch;
use strict;
use base 'Class::Accessor::Fast';

use overload
    '""' => sub { shift->str; },
    fallback => 1;

our ($STOPMIN, $STOPMAX, $STOPWORDS);
our $MAX_FREEMATCH_TERMS = Bibliotech::Config->get('MAX_FREEMATCH_TERMS') || 12;

__PACKAGE__->mk_accessors(qw/str terms/);

sub new {
  my ($class, $str) = @_;
  return unless $str;
  ($STOPMIN, $STOPMAX, $STOPWORDS) = init_stopwords() unless defined $STOPMIN;
  my @raw_terms = split(/[,\s\'\"]+/, $str);
  my @terms = grep(length($_) >= $STOPMIN && length($_) <= $STOPMAX && !$STOPWORDS->{lc $_}, @raw_terms);
  splice @terms, $MAX_FREEMATCH_TERMS if $MAX_FREEMATCH_TERMS and @terms > $MAX_FREEMATCH_TERMS;
  return $class->SUPER::new({str => $str, terms => \@terms});
}

# get some variables from MySQL that are controlling for FULLTEXT indexes
sub init_stopwords {
  my %mysql;
  {
    my $sth = Bibliotech::DBI->db_Main->prepare('SHOW VARIABLES LIKE ?');
    $sth->execute('ft_%');
    while (my ($key, $value) = $sth->fetchrow_array) {
      $mysql{$key} = $value;
    }
  }
  my %words;
  if (my $file = $mysql{ft_stopword_file}) {
    if (open FILE, "<$file") {
      while (<FILE>) {
	chomp;
	foreach (split(/[,\s]+/)) {
	  $words{lc $_} = 1;
	}
      }
      close FILE;
    }
  }
  return ($mysql{ft_min_word_len}, $mysql{ft_max_word_len}, \%words);
}

1;
__END__
