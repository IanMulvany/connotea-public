use strict;
use Bibliotech::CitationSource;

package Bibliotech::CitationSource::Wiley;
use base 'Bibliotech::CitationSource';

use LWP;
use HTTP::Request::Common;
use HTTP::Cookies;

use constant CIT_APP => 'http://www3.interscience.wiley.com/tools/CitEx?';
use constant APP_FLAGS => 'clienttype=1&subtype=1&mode=1&version=1';

#
# constants for form
#
#	'format'
use constant PLAIN_TEXT => '1';
use constant END_NOTE => '3';
#	'type'
use constant CITATION => '1';
use constant CITATION_AND_ABSTRACT => '2';
#	'file'
use constant PC => '1';
use constant MAC => '2';
use constant UNIX => '3';


sub api_version {
  1;
}

sub name {
  'Wiley';
}

sub understands {
  my ($self, $uri) = @_;
  return 0 unless $uri->scheme =~ /^http$/i;
  return 0 unless $uri->host =~ m/^(www3\.)?interscience\.wiley\.com$/;
  return 1 if $uri->path =~ m!^/cgi-bin/(abstract|fulltext)/.+!i;
  return 0;
}

sub citations {
  my ($self, $article_uri) = @_;

  my $text;
  eval {
    my $file = $article_uri->path;

    die "no file name seen in URI\n" unless $file;

    # for now assuming id starts with first digit, to forward slash
    #   ex: /cgi-bin/abstract/10049442/ABSTRACT/
    my ($id) = $file =~ /(\d.*?)\//;

    #
    # hit form to set cookies
    #	ID is retained outside of usual form parameters
    #
    my $cookieJar = new HTTP::Cookies();
    my ($ua) = $self->ua;
    $ua->cookie_jar($cookieJar);

    my $response = $ua->request(GET CIT_APP . APP_FLAGS . "&id=" . $id . "&redirect=" . $file);

    #
    # now post form with parameters set
    #
    my ($response) = $ua->request(POST CIT_APP,
				  ['mode'    	    => '2',
				   'format'  	    => PLAIN_TEXT, 
				   'type'    	    => CITATION, 
				   'file'           => PC,
				   'exportCitation' => 'submit']);
    if ($response->is_success) {
      my $raw_text = $response->content;
      $text = new Bibliotech::CitationSource::Wiley::TEXT ($raw_text);
    } else {
      die $response->status_line;
    }
  };    
  #die $@ if $@ =~ /at .* line \d+/;

  $self->errstr($@), return undef if $@;
  return bless [bless $text, 'Bibliotech::CitationSource::Wiley::Result'], 'Bibliotech::CitationSource::ResultList';
}


#
# text structure is very similar to RIS structure
#	model parser after NPG::RIS package
#

package Bibliotech::CitationSource::Wiley::TEXT;
use base 'Class::Accessor::Fast';
# read the TEXT file and provide back an object that is a hashref of the tags,
# using arrayrefs for tags with multiple values

__PACKAGE__->mk_accessors(qw/ID T1 TI CT BT T2 BT T3 A1 AU A2 ED A3 Y1 PY Y2 N1 AB N2 KW RP JF JO JA J1 J2
			  VL IS SP EP CP CY PB SN AD AV M1 M2 M3 U1 U2 U3 U4 U5 UR L1 L2 L3 L4 CP DOI YR SO PG NO US
			  has_data inceq/);

sub new {
  my ($class, $data) = @_;
  my $self = {};
  bless $self, ref $class || $class;
  $self->has_data(0);
  $self->inceq(0);  # "include equivalents" - when calling title() do we return just T1 or all of T1, TI, CT, BT

  $self->parse($data) if $data;
  return $self;
}

sub parse {
  my ($self, $data) = @_;
  my @lines;

  #
  # this is simplified for Wiley (I didn't understand all of the double_newlines and in_data logic
  #		it may become clearer with more testing/use
  #
  @lines = ref $data ? map { s/\r?\n$//; $_; } @{$data} : split(/\r?\n/, $data);
  foreach (@lines) {
    my ($key, $value) = /^(\w\w\w?): (.*)$/;
    next unless $self->can($key);
    my $stored = $self->$key;
    if (defined $stored) {
      if (ref $stored) {
		push @{$stored}, $value;
      }
      else {
		$stored = [$stored, $value];
      }
    }
    else {
      $stored = $value;
    }
    $self->$key($stored);
  }
  return $self;
}

sub collect {
  my ($self, @fields) = @_;
  my $include = $self->inceq;
  my $soft = 0;
  if ($fields[0] eq 'soft') {
    shift @fields;
    $soft = 1;
  }
  if (($soft and $include >= 2) or (!$soft and $include >= 1)) {
    my @results;
    foreach my $field (@fields) {
      my $stored = $self->$field;
      next unless defined $stored;
      push @results, ref $stored ? @{$stored} : $stored;
    }
    return wantarray ? () : undef unless @results;
    return wantarray ? @results : \@results;
  }
  else {
    foreach my $field (@fields) {
      my $stored = $self->$field;
      return $stored if defined $stored;
    }
    return wantarray ? () : undef;
  }
}

#
# subroutines copied from NPG::RIS results
#	some labels were the same, some were different (changed/added), some did not exist so far (hence the ?? notation)
#
sub title_primary    { Bibliotech::Util::ua_clean_title(shift->collect(qw/T1 TI CT BT/)) }  # TI
sub title_secondary  { shift->collect(qw/T2 BT/); }	#??
sub title_series     { shift->collect(qw/T3/); }	#??
sub title      	     { shift->collect(soft => qw/title_primary title_secondary title_series/); }
sub author_primary   { shift->collect(qw/A1 AU/); }	# AU
sub author_secondary { shift->collect(qw/A2 ED/); }	#??
sub author_series    { shift->collect(qw/A3/); }	#??
sub author           { shift->collect(soft => qw/author_primary author_secondary author_series/); }
sub authors          { shift->collect(qw/author/); }
sub date_primary     { shift->collect(qw/YR/); }	# YR (changed)
sub date_secondary   { shift->collect(qw/Y2/); }	#??
sub date             { shift->collect(soft => qw/date_primary date_secondary/); }
sub notes            { shift->collect(qw/N1 AB/); }	#??
sub abstract         { shift->collect(qw/N2/); }	#?? didn't pull abstract
sub keywords         { shift->collect(qw/KW/); }	#??
sub reprint          { shift->collect(qw/RP/); }	#??
sub periodical_name  { shift->collect(qw/SO/); }	# SO (changed)
sub periodical_abbr  { shift->collect(qw/JA J1 J2/); }	#??
sub journal          { shift->collect(soft => qw/periodical_name periodical_abbr/); }
sub journal_abbr     { shift->collect(qw/periodical_abbr/); }
sub volume           { shift->collect(qw/VL/); }	# VL
sub issue            { shift->collect(qw/NO/); }	# NO (changed)
sub page_range    	 { shift->collect(qw/PG/); }	# PG (changed) range ex. 351-360
#sub starting_page    { shift->collect(qw/PG/); }	# PG (changed) range ex. 351-360
#sub ending_page      { shift->collect(qw/EP/); }	#?? in range
#sub page             { shift->collect(qw/starting_page/); }
sub publication_city { shift->collect(qw/CY/); }	#?? took CP out
sub publisher        { shift->collect(qw/PB/); }	#??
sub issn_or_isbn     { shift->collect(qw/SN/); }	#?? ON? PN?
sub issn             { shift->collect(qw/issn_or_isbn/); }
sub isbn             { shift->collect(qw/issn_or_isbn/); }
sub address          { shift->collect(qw/AD/); }	# AD
sub availablity      { shift->collect(qw/AV/); }	#??
sub url              { shift->collect(qw/US/); }	# US (changed)
sub uri              { shift->collect(qw/url/); }
sub web              { shift->collect(qw/url/); }
sub pdf              { shift->collect(qw/L1/); }	#??
sub full_text        { shift->collect(qw/L2/); }	#??
sub related          { shift->collect(qw/L3/); }	#??
sub image            { shift->collect(qw/L4/); }	#??
sub links            { shift->collect(qw/web pdf full_text related image/); }
sub copy        	 { shift->collect(qw/CP/); }	# CP (added)
sub copyright        { shift->collect(qw/copy/); }
sub doi        	 	 { shift->collect(qw/DOI/); }	# DOI (added)
sub identification   { shift->collect(qw/doi/); }

package Bibliotech::CitationSource::Wiley::Result;
use base ('Bibliotech::CitationSource::Wiley::TEXT', 'Bibliotech::CitationSource::Result');

sub type {
  'Wiley';
}

sub source {
  'Wiley Plain Text file from www3.interscience.wiley.com';
}

sub identifiers {
  {doi => shift->doi};
}

sub justone {
  my ($self, $field) = @_;
  my $super = 'SUPER::'.$field;
  my $stored = $self->$super or return undef;
  return ref $stored ? $stored->[0] : $stored;
}

sub authors {
  my ($self) = @_;
  my $authors = $self->SUPER::authors;

  # for wiley, authors come in comma separated string
  if ($authors =~ ',') {
    my @a = split(/,/, $authors);
    $authors = \@a;
  }

  my @authors = map(Bibliotech::CitationSource::Wiley::Result::Author->new($_), ref $authors ? @{$authors} : $authors);
  bless \@authors, 'Bibliotech::CitationSource::Result::AuthorList';
}

sub journal {
  my ($self) = @_;
  return Bibliotech::CitationSource::Wiley::Result::Journal->new($self->justone('journal'),
								 $self->justone('journal_abbr'),
								 $self->justone('issn'));
}

sub pubmed  { undef; }
sub title   { shift->justone('title'); }
sub volume  { shift->justone('volume'); }
sub issue   { shift->justone('issue'); }
sub page    { shift->page_range; }
sub url     { shift->url; }

sub last_modified_date {
  undef;
}

package Bibliotech::CitationSource::Wiley::Result::Author;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/firstname forename initials lastname/);

sub new {
  my ($class, $author) = @_;
  my $self = {};
  bless $self, ref $class || $class;
  my ($lastname, $firstname, $initials);
  $author =~ s/^\s*//;
  if ($author =~ /^(.+?\s*\w\.)\s+(.*)$/) {
    ($firstname, $lastname) = ($1, $2);
  }
  elsif ($author =~ /^(.+?)\s+(.+)$/) {
    ($firstname, $lastname) = ($1, $2);
  }
  elsif ($author =~ /^(.*)\s+(.+)$/) {
    ($firstname, $lastname) = ($1, $2);
  }
  else {
    $lastname = $author;
  }
  $self->forename($firstname) if $firstname;
  my $initials = join(' ', map { s/^(.).*$/$1/; $_; } split(/\s+/, $firstname)) || undef;
  $self->firstname($firstname);
  $self->lastname($lastname);
  $self->initials($initials);
  return $self;
}

package Bibliotech::CitationSource::Wiley::Result::Journal;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/name medline_ta issn/);

sub new {
  my ($class, $name, $medline_ta, $issn) = @_;
  my $self = {};
  bless $self, ref $class || $class;
  $self->name($name);
  #$self->medline_ta($medline_ta);
  $self->issn($issn);
  return $self;
}

1;
__END__
