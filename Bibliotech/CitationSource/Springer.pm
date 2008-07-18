use strict;
use Bibliotech::CitationSource;
use Bibliotech::CitationSource::NPG;


package Bibliotech::CitationSource::Springer;
use base 'Bibliotech::CitationSource';
use URI;
use URI::QueryParam;

#
# Site depends on session cookie
#
use HTTP::Request::Common;
use HTTP::Cookies;

# ex. http://www.springerlink.com/export.mpx?code=mn2876332r756010&mode=ris
use constant SPRINGER_HOST => 'http://www.springerlink.com/';
use constant GET_RIS_APP => 'export.mpx?';

sub api_version {
  1;
}

sub name {
  'Springer';
}

sub understands {
  my ($self, $uri) = @_;
  return 0 unless $uri->scheme =~ /^http$/i;
  return 0 unless $uri->host =~ m/^(www\.)?springerlink\.com$/ or $uri->host =~ m/dx.doi.org/;

  # ex. http://www.springerlink.com/content/mn2876332r756010/?p=32e7a3b916fa464f9418d96e12c3041e&pi=1
  #return 1 if ($uri->path =~ m!^/content/.*?/\?p=.+?!i);
  # SUE books?  other types of content? what is valid?
  return 1 if $uri->path =~ m!^/content/.*?/!i or $uri->path =~ m!^/10\.\d{4}/.+!;

  return 0;
}

#
# This needs to be used in springer to get UR from ris file, instead of ugly url
#
sub filter {
  my ($self, $uri) = @_;

  $self->clear_ris_content;
  my $ris = $self->get_ris_content($uri);

  my $url = $ris->{UR};
  $url ? return new URI($url) : undef;
}

sub citations {
  my ($self, $article_uri) = @_;

  my $ris;
  eval {
    $self->errstr('do not understand URI'), return undef unless $self->understands($article_uri);
    #die "do not understand URI\n" unless $self->understands($article_uri);

    $ris = $self->get_ris_content($article_uri);

    my $doi = $self->get_id($ris->{'UR'});
    $doi =~ s/^doi://;
    $ris->{M3}=$doi;
  };    
  die $@ if $@ =~ /at .* line \d+/;
  $self->errstr($@), return undef if $@;
  return bless [bless $ris, 'Bibliotech::CitationSource::Springer::Result'], 'Bibliotech::CitationSource::ResultList';
}

#
#	to get doi from string
#		looking at two ways
#		1) first one is from the first Springer routine, probably not needed
#		2) second one looks at RIS UR element
sub get_id {
  my ($self, $string) = @_;

  my $id;
  ($id) = $string =~ m/&id=(.*?)&/g;

  # to get doi
  ($id) = $string =~ m!/(10\.\d{4}/.+)! unless $id;

  return $id;
}

sub clear_ris_content {
  my ($self) = @_;
  undef $self->{RIS};
}

sub get_ris_content {
  my ($self, $uri) = @_;

  #
  # do we already have it?
  #
  return $self->{RIS} if $self->{RIS};

  my $file = $uri->path;

  die "no file name seen in URI\n" unless $file;

  my $cookieJar = new HTTP::Cookies();
  my ($ua) = Bibliotech::Util::ua($self->bibliotech);
  $ua->cookie_jar($cookieJar);

  #
  # set/get session cookie (among others that may be automatically set)
  #
  my $res = $ua->request(GET $uri);

  #
  # id for code in ris call seems to be the value after "/content/"
  #
  my ($session) = $file =~  m!/content/(.*?)/!i;

  # http://www.springerlink.com/export.mpx?code=mn2876332r756010&mode=ris
  my $query_uri = URI->new(SPRINGER_HOST.GET_RIS_APP.'code='.$session.'&mode=ris');

  my $ris_raw = $ua->request(POST $query_uri);
  my $ris = new Bibliotech::CitationSource::NPG::RIS ($ris_raw->content);

  die "RIS obj false\n" unless $ris;
  die "RIS file contained no data\n" unless $ris->has_data;

  bless $self->{RIS} = $ris;
  return $self->{RIS};
}

package Bibliotech::CitationSource::Springer::Result;
use base ('Bibliotech::CitationSource::NPG::RIS', 'Bibliotech::CitationSource::Result');

sub type {
  'Springer';
}

sub source {
  'Springer RIS file from www.springerlink.com';
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
  my @authors = map(Bibliotech::CitationSource::Springer::Result::Author->new($_), ref $authors ? @{$authors} : $authors);
  bless \@authors, 'Bibliotech::CitationSource::Result::AuthorList';
}

# override - from Nature the abbreviated name arrives in JO
sub periodical_name  { shift->collect(qw/JF/); }
sub periodical_abbr  { shift->collect(qw/JO JA J1 J2/); }

sub journal {
  my ($self) = @_;
  return Bibliotech::CitationSource::Springer::Result::Journal->new($self->justone('journal'),
								    $self->justone('journal_abbr'),
								    $self->justone('issn'));
}

sub pubmed  { undef; }
sub doi     { shift->justone('misc3'); }
sub title   { shift->justone('title'); }
sub volume  { shift->justone('volume'); }
sub issue   { shift->justone('issue'); }
sub page    { shift->page_range; }
sub url     { shift->collect(qw/UR L3/); }

sub date {
  my $date = shift->justone('date');
  $date =~ s|^(\d+/\d+/\d+)/.*$|$1|;
  return $date;
}

sub last_modified_date {
  shift->date(@_);
}

package Bibliotech::CitationSource::Springer::Result::Author;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/firstname forename initials lastname/);

sub new {
  my ($class, $author) = @_;
  my $self = {};
  bless $self, ref $class || $class;
  my ($lastname, $firstname);
  if ($author =~ /^(.+?),\s*(.*)$/) {
    ($lastname, $firstname) = ($1, $2);
  }
  elsif ($author =~ /^(.*)\s+(.+)$/) {
    ($firstname, $lastname) = ($1, $2);
  }
  else {
    $lastname = $author;
  }
  my $initials = join(' ', map { s/^(.).*$/$1/; $_; } split(/\s+/, $firstname)) || undef;
  $self->forename($firstname) if $firstname;
  $firstname =~ s/(\s\w\.?)+$//;
  $self->firstname($firstname);
  $self->lastname($lastname);
  $self->initials($initials);
  return $self;
}

package Bibliotech::CitationSource::Springer::Result::Journal;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/name medline_ta issn/);

sub new {
  my ($class, $name, $medline_ta, $issn) = @_;
  my $self = {};
  bless $self, ref $class || $class;
  $self->name($name);
  $self->medline_ta($medline_ta);
  $self->issn($issn);
  return $self;
}

1;
__END__
