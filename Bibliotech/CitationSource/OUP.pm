use strict;
use Bibliotech::CitationSource;
use Bibliotech::CitationSource::NPG;


package Bibliotech::CitationSource::OUP;
use base 'Bibliotech::CitationSource';
use URI;
use URI::QueryParam;

sub api_version {
  1;
}

sub name {
  'OUP';
}

sub version {
  '1.3';
}

sub understands {
  my ($self, $uri) = @_;
  return 0 unless $uri->scheme eq 'http';
  return 0 unless Bibliotech::CitationSource::OUP::HostTable::defined($uri->host);
  return 1 if $uri->path =~ m!^/cgi/((content/(short|extract|abstract|full))|reprint)/.+!i;
  return 0;
}

sub citations {
  my ($self, $article_uri) = @_;

  my $ris;
  eval {
    my $file = $article_uri->path;
    $file =~ s/\.html(?:#|\?).*/.html/;  # strip fragments or queries

    die "no file name seen in URI\n" unless $file;

    #for now assuming id starts with first digit
    #	ex: cgi/content/abstract/102/18/6251
    my ($id) = $file =~ /(\d.*$)/;

    my $ris_host = Bibliotech::CitationSource::OUP::HostTable::getRISPrefix($article_uri->host);
    my $query_uri = URI->new('http://'.$article_uri->host.'/cgi/citmgr_refman?gca='.$ris_host.';'.$id);

    my $ris_raw = $self->get($query_uri);
    $ris = Bibliotech::CitationSource::NPG::RIS->new($ris_raw);
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
  return bless [bless $ris, 'Bibliotech::CitationSource::OUP::Result'], 'Bibliotech::CitationSource::ResultList';
}


package Bibliotech::CitationSource::OUP::Result;
use base ('Bibliotech::CitationSource::NPG::RIS', 'Bibliotech::CitationSource::Result');

sub type {
  'OUP';
}

sub source {
  'OUP RIS file from www.pnas.org';
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
  my @authors = map(Bibliotech::CitationSource::OUP::Result::Author->new($_), ref $authors ? @{$authors} : $authors);
  bless \@authors, 'Bibliotech::CitationSource::Result::AuthorList';
}

# override - from Nature the abbreviated name arrives in JO
sub periodical_name  { shift->collect(qw/JF/); }
sub periodical_abbr  { shift->collect(qw/JO JA J1 J2/); }

sub journal {
  my ($self) = @_;
  return Bibliotech::CitationSource::OUP::Result::Journal->new($self->justone('journal'),
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

package Bibliotech::CitationSource::OUP::Result::Author;
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

package Bibliotech::CitationSource::OUP::Result::Journal;
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

package Bibliotech::CitationSource::OUP::HostTable;

# Bioinformatics
# Nucleic Acids Research
# Brain 
# JNCI Cancer Spectrum 
# The Journal of Biochemistry
# Cerebral Cortex
# Molecular Biology and Evolution


%Bibliotech::CitationSoure::OUP::HostTable::Hosts = (
   	'bioinformatics.oupjournals.org' 	=> 'bioinfo',
  	'nar.oupjournals.org'				=> 'nar',
  	'brain.oupjournals.org'				=> 'brain',
  	'jncicancerspectrum.oupjournals.org'	=> 'jnci',
  	'jb.oupjournals.org'				=> 'jbiochem',
  	'cercor.oupjournals.org'			=> 'cercor',
  	'mbe.oupjournals.org'				=> 'molbiolevol',
);
my($hRef) = \%Bibliotech::CitationSoure::OUP::HostTable::Hosts;

sub defined {
  my ($host) = @_;
  return defined($hRef->{_without_www($host)});
}

sub getRISPrefix {
  my ($host) = @_;
  return $hRef->{_without_www($host)};
}

sub _without_www {
  local $_ = shift;
  s/^www.//;
  return $_;
}

1;
__END__
