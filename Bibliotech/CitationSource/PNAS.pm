use strict;
use Bibliotech::CitationSource;
use Bibliotech::CitationSource::NPG;


package Bibliotech::CitationSource::PNAS;
use base 'Bibliotech::CitationSource';
use URI;
use URI::QueryParam;
use Data::Dumper;

sub api_version {
  1;
}

sub name {
  'PNAS';
}

sub version {
  '1.3';
}

sub understands {
  my ($self, $uri) = @_;

  return 0 unless $uri->scheme eq 'http';

  #check the host
  return 0 unless ($uri->host =~ m/^(www\.)?pnas\.org$/);
  #check the path
  return 1 if ($uri->path =~ m!^/cgi/((content/(short|extract|abstract|full))|reprint)/.+!i);
  return 0;
}

sub citations {
  my ($self, $article_uri) = @_;

  my $ris;
  eval {
    die "do not understand URI\n" unless $self->understands($article_uri);

    my $file;
	$file = $article_uri->path;
	#strip fragments or queries
	$file =~ s/(?:#|\?).*//;

    die "no file name seen in URI\n" unless $file;

	#for now assuming id starts with first digit
	#	ex: cgi/content/abstract/102/18/6251
	my($id) = $file =~ /(\d.*$)/;

	my $query_uri = new URI("http://www.pnas.org/cgi/citmgr_refman?gca=pnas;" . $id);

	my $ris_raw = $self->get($query_uri);
    $ris = new Bibliotech::CitationSource::NPG::RIS ($ris_raw);
    if (!$ris->has_data) {
      # give it one more try 
      sleep 2;
      $ris_raw = $self->get($query_uri);
      $ris = new Bibliotech::CitationSource::NPG::RIS ($ris_raw);
    }
    die "RIS obj false\n" unless $ris;
    die "RIS file contained no data\n" unless $ris->has_data;
  };    
  die $@ if $@ =~ /at .* line \d+/;

  $self->errstr($@), return undef if $@;
  return bless [bless $ris, 'Bibliotech::CitationSource::PNAS::Result'], 'Bibliotech::CitationSource::ResultList';
}


package Bibliotech::CitationSource::PNAS::Result;
use base ('Bibliotech::CitationSource::NPG::RIS', 'Bibliotech::CitationSource::Result');

sub type {
  'PNAS';
}

sub source {
  'PNAS RIS file from www.pnas.org';
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
  my @authors = map(Bibliotech::CitationSource::PNAS::Result::Author->new($_), ref $authors ? @{$authors} : $authors);
  bless \@authors, 'Bibliotech::CitationSource::Result::AuthorList';
}

# override - from Nature the abbreviated name arrives in JO
sub periodical_name  { shift->collect(qw/JF/); }
sub periodical_abbr  { shift->collect(qw/JO JA J1 J2/); }

sub journal {
  my ($self) = @_;
  return Bibliotech::CitationSource::PNAS::Result::Journal->new($self->justone('journal'),
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

package Bibliotech::CitationSource::PNAS::Result::Author;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/firstname initials lastname/);

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
  $firstname =~ s/(\s\w\.?)+$//;
  $self->firstname($firstname);
  $self->lastname($lastname);
  $self->initials($initials);
  return $self;
}

package Bibliotech::CitationSource::PNAS::Result::Journal;
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
