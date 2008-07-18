use strict;
use Bibliotech::CitationSource;
use Bibliotech::CitationSource::NPG;


package Bibliotech::CitationSource::Blackwell;
use base 'Bibliotech::CitationSource';
use URI;
use URI::QueryParam;
use LWP;
use HTTP::Request::Common;
use HTTP::Cookies;

sub api_version {
  1;
}

sub name {
  'Blackwell';
}

sub understands {
  my ($self, $uri) = @_;
  return 0 unless $uri->scheme =~ /^http$/i;
  return 0 unless $uri->host =~ m/^(www\.)?blackwell-synergy\.com$/;

  # ex: doi/abs/10.1111/j.1600-0501.2005.01111.x
  # ex: doi/10.1111/j.1523-1755.2005.00267.x/full
  return 1 if $uri->path =~ m!/doi/.+!i;

  # ex. http://www.blackwell-synergy.com/servlet/useragent?func=synergy&synergyAction=showAbstract&doi=10.1046/j.1365-2486.2002.00492.x
  return 1 if $uri->query_param('doi');

  return 0;
}

sub citations {
  my ($self, $article_uri) = @_;

  my $ris;
  eval {
    die "do not understand URI\n" unless $self->understands($article_uri);

    my $file = $article_uri->path;

    die "no file name seen in URI\n" unless $file;

    my ($id);
    if ($article_uri->query && $article_uri->query_param('doi')) {
      $id = $article_uri->query_param('doi');
    } else {
      # ex: 10.1111/j.1523-1755.2005.00267.x
      # ex: 10.1111/j.1523-1755.2005.00267.x/full
      # ignore anything after the second slash if it exists (doi has on slash in it)
      ($id) = $file =~ /(\d.*?\/.*?)(\/.*?)?$/;
    }

    die "no doi\n" unless $id;	# will set errstr, die

    my $cookieJar = new HTTP::Cookies();
    my $ua = $self->ua;
    $ua->cookie_jar($cookieJar);

    #
    # set/get session cookie (among others that may be automatically set)
    #
    my $res = $ua->request(GET 'http://'.$article_uri->host);

    #
    # check for problem with request
    #
    if ($res->is_success) {
      $res = $ua->request(POST 'http://'.$article_uri->host.'/action/downloadCitation',
			  ['doi'     => $id,
			   'include' => 'cit',
			   'format'  => 'refman',
			   'direct'  => 'checked',
			   'submit'  => 'Download references']);

      $ris = Bibliotech::CitationSource::NPG::RIS->new($res->content);
      die "RIS obj false\n" unless $ris;
      die "RIS file contained no data\n" unless $ris->has_data;
      $ris->{M3} = $id;
    } else {
      die $res->status_line;
    }
  };    
  die $@ if $@ =~ /at .* line \d+/;
  $self->errstr($@), return undef if $@;
  return bless [bless $ris, 'Bibliotech::CitationSource::Blackwell::Result'], 'Bibliotech::CitationSource::ResultList';
}


package Bibliotech::CitationSource::Blackwell::Result;
use base ('Bibliotech::CitationSource::NPG::RIS', 'Bibliotech::CitationSource::Result');

sub type {
  'Blackwell';
}

sub source {
  'Blackwell RIS file from www.blackwell-synergy.com';
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
  my @authors = map(Bibliotech::CitationSource::Blackwell::Result::Author->new($_), ref $authors ? @{$authors} : $authors);
  bless \@authors, 'Bibliotech::CitationSource::Result::AuthorList';
}

sub journal {
  my ($self) = @_;
  return Bibliotech::CitationSource::Blackwell::Result::Journal->new($self->justone('journal'),
							 $self->justone('journal_abbr'),
							 $self->justone('issn'));
}

sub pubmed  { undef; }
sub doi     { shift->justone('misc3'); }
sub title   { shift->justone('title'); }
sub volume  { shift->justone('volume'); }
sub issue   { shift->justone('issue'); }
sub page    { shift->page_range; }
sub url     { shift->justone('ur'); }

sub date {
  my $date = shift->justone('date');
  $date =~ s|^(\d+/\d+/\d+)/.*$|$1|;
  return $date;
}

sub last_modified_date {
  shift->date(@_);
}

package Bibliotech::CitationSource::Blackwell::Result::Author;
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
  $self->forename($firstname);
  $firstname =~ s/(\s\w\.?)+$//;
  $self->firstname($firstname);
  $self->lastname($lastname);
  $self->initials($initials);
  return $self;
}

package Bibliotech::CitationSource::Blackwell::Result::Journal;
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
