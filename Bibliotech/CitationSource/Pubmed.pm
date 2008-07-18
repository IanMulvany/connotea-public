# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::Pubmed class retrieves citation data for articles
# in Pubmed.

use strict;
use Bibliotech::CitationSource;
use Bio::Biblio::IO;

package Bibliotech::CitationSource::Pubmed;
use base 'Bibliotech::CitationSource';
use URI;
use URI::QueryParam;
use Bibliotech::Config;

our $SITE_NAME  = Bibliotech::Config->get('SITE_NAME');
our $SITE_EMAIL = Bibliotech::Config->get('SITE_EMAIL');

sub api_version {
  1;
}

sub name {
  'Pubmed';
}

sub version {
  '2.2';
}

sub understands {
  my ($self, $uri, $content_sub) = @_;

  return 5 if $uri =~ /^\d+$/;  # not a URL but a raw PMID, number only ... return a true but suboptimal score

  my $scheme = $uri->scheme or return 0;
  return 1 if $scheme =~ /^pm(?:id)?$/i;
  return 1 if $scheme eq 'info' and $uri->path =~ m|^pmid/|;
  return 0 unless $scheme eq 'http';
  
  my $host = $uri->host or return 0;
  return 0 unless $host =~ /^(view|www|eutils)\.ncbi\.nlm\.nih\.gov(?:\.(?:lib|ez)?proxy\..+)?$/;

  my ($db, $id) = _db_and_id_from_url($uri);
  return 1 if $db and $id and $self->understands_id({db => $db, pubmed => $id});

  if (lc($uri->query_param('cmd')||'') eq 'search' and $uri->query_param('term')) {
    return 1 if is_search_page_with_one_result($content_sub);
  }

  return 0;
}

sub is_search_page_with_one_result {
  my $content_sub = shift or return;
  my ($response) = $content_sub->();
  return unless $response->is_success;
  my $content = $response->content;
  my @uids;
  while ($content =~ /<dd class="abstract".*PMID: (\d+)/gs) {
    push @uids, $1;
  }
  return unless @uids == 1;
  return $uids[0];
}

sub understands_id {
  my ($self, $id_hashref) = @_;
  return 0 unless $id_hashref and ref $id_hashref;
  my $db = $id_hashref->{db} or return 0;
  return 0 unless lc($db) eq 'pubmed';
  my $id = $id_hashref->{pubmed} or return 0;
  return 0 unless $id =~ /^\d+$/;
  return 1;
}

sub filter {
  my ($self, $uri) = @_;
  return unless $uri;
  return _url_from_pmid('view', 'pubmed', "$uri") if $uri =~ /^\d+$/;
  my $scheme = $uri->scheme or return;
  return _url_from_pmid('view', 'pubmed', $uri->opaque) if $scheme =~ /^pm(?:id)?$/i;
  return _url_from_pmid('view', 'pubmed', do { $uri->path =~ m|^pmid/(.*)$|; $1; }) if $scheme eq 'info';
  return;
}

sub _clean_db_str {
  local $_ = shift or return;
  s/\W//g;
  return $_;
}

sub _clean_single_id_str {
  local $_ = shift or return;
  return if m/,/;  # multiple
  s/\%20/ /g;
  s/\D//g;
  return $_;
}

sub _url_from_pmid {
  my $purpose = shift;
  my $db = _clean_db_str(shift) || 'pubmed';
  my $id = _clean_single_id_str(shift);
  return URI->new('http://www.ncbi.nlm.nih.gov/'.$db.'/'.$id) if $purpose eq 'view';
  return URI->new('http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?retmode=xml&db='.$db.'&id='.$id);
}

sub url_add_tool {
  my ($self, $url) = @_;
  my $bibliotech = $self->bibliotech;
  if (my $sitename = defined $bibliotech ? $bibliotech->sitename : $SITE_NAME) {
    $sitename =~ s/\W/_/g;
    $url->query_param(tool => $sitename);
  }
  if (my $siteemail = defined $bibliotech ? $bibliotech->siteemail : $SITE_EMAIL) {
    $url->query_param(email => $siteemail);
  }
  return $url;
}

sub _db_and_id_from_url {
  my $uri = shift;
  if (my $path = $uri->path) {
    return ($1, _clean_single_id_str($2)) if $path =~ m|^/(pubmed)/([\d,]+)|;
  }
  return (_clean_db_str($uri->query_param('db') ||
			$uri->query_param('Db')) || undef,
	  _clean_single_id_str($uri->query_param('uid') ||
			       $uri->query_param('list_uids') ||
			       _pmid_in_term($uri->query_param('term') ||
					     $uri->query_param('Term') ||
					     $uri->query_param('TermToSearch'))) || undef);
}

sub _pmid_in_term {
  local $_ = shift or return;
  /(\d+)/ and return $1;
  return;
}

sub citations {
  my ($self, $article_uri, $content_sub) = @_;
  my ($db, $id) = _db_and_id_from_url($article_uri);
  $id ||= is_search_page_with_one_result($content_sub);
  return undef unless $db and $id;
  return $self->citations_id({db => $db, pubmed => $id});
}

sub citations_id {
  my ($self, $id_hashref) = @_;

  my $io = eval {
    die "do not understand id\'s\n" unless $self->understands_id($id_hashref);
    my $query_uri = $self->url_add_tool(_url_from_pmid('fetch', $id_hashref->{db}, $id_hashref->{pubmed}));
    #warn "$query_uri\n";
    my $xml = $self->get($query_uri) or die "XML retrieval failed\n";
    die "Error message from Pubmed server ($query_uri): $1\n" if $xml =~ m|<Error[^>]*>(.*)</Error>|si;
    my $obj = Bio::Biblio::IO->new(-data => $xml, -format => 'pubmedxml') or die "IO object false\n";
    return $obj;
  };
  if (my $e = $@) {
    die $e if $e =~ /at .* line \d+/;
    $self->errstr($e);
    return undef;
  }

  # we cannot simply rebless as I'd prefer because Bioperl uses child classes
  return Bibliotech::CitationSource::Pubmed::ResultList->new($io);
}

package Bibliotech::CitationSource::Pubmed::ResultList;
use base ('Class::Accessor::Fast', 'Bibliotech::CitationSource::ResultList');

__PACKAGE__->mk_accessors(qw/io/);

sub new {
  my ($class, $io) = @_;
  my $self = bless {}, ref $class || $class;
  $self->io($io);
  return $self;
}

sub fetch {
  my $article = shift->io->next_bibref or return undef;
  # we cannot simply rebless as I'd prefer because Bioperl uses child classes
  return Bibliotech::CitationSource::Pubmed::Result->new($article);
}

package Bibliotech::CitationSource::Pubmed::Result;
use base ('Class::Accessor::Fast', 'Bibliotech::CitationSource::Result');

__PACKAGE__->mk_accessors(qw/article/);

sub new {
  my ($class, $article) = @_;
  my $self = bless {}, ref $class || $class;
  $self->article($article);
  return $self;
}

sub type {
  'Pubmed';
}

sub source {
  'Pubmed database at eutils.ncbi.nlm.nih.gov';
}

sub identifiers {
  my ($self) = @_;
  my %id;
  foreach (@{$self->article->pubmed_article_id_list}) {
    $id{lc($_->{idType})} = $_->{id};
  }
  return \%id;
}

# base class version would work, this is just an miniscule bit more efficient
sub identifier {
  my ($self, $key) = @_;
  $key = lc $key;
  foreach (@{$self->article->pubmed_article_id_list}) {
    return $_->{id} if lc($_->{idType}) eq $key;
  }
  return undef;
}

sub page   { shift->article->medline_page; }
sub title  { shift->article->title; }
sub volume { shift->article->volume; }
sub issue  { shift->article->issue; }
sub date   { shift->article->date; }
sub last_modified_date { shift->article->last_modified_date; }

sub authors {
  my $authors = shift->article->authors || [];
  my $new_authors = Bibliotech::CitationSource::Result::AuthorList->new;
  foreach my $author (@{$authors}) {
    $new_authors->push(Bibliotech::CitationSource::Pubmed::Result::Author->new($author));
  }
  return $new_authors;
}

sub journal {
  my $journal = shift->article->journal or return undef;
  return Bibliotech::CitationSource::Pubmed::Result::Journal->new($journal);
}

package Bibliotech::CitationSource::Pubmed::Result::Author;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/author/);

sub new {
  my ($class, $author) = @_;
  my $self = bless {}, ref $class || $class;
  $self->author($author);
  return $self;
}

sub AUTOLOAD {
  (my $name = our $AUTOLOAD) =~ s/.*:://;
  return if $name eq 'DESTROY';
  my $self = shift;
  my $author = $self->author;
  return $author->$name(@_) if $author->can($name);
  no strict 'refs';
  return &{'Bibliotech::CitationSource::Result::Author::'.$name}(@_) if Bibliotech::CitationSource::Result::Author->can($name);
  return if $name eq 'surname';  # it can't, but we use this in testing, avoid next line
  die 'cannot handle '.$name;
}

package Bibliotech::CitationSource::Pubmed::Result::Journal;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/journal/);

sub new {
  my ($class, $journal) = @_;
  my $self = bless {}, ref $class || $class;
  $self->journal($journal);
  return $self;
}

sub AUTOLOAD {
  (my $name = our $AUTOLOAD) =~ s/.*:://;
  return if $name eq 'DESTROY';
  my $self = shift;
  my $journal = $self->journal;
  return $journal->$name(@_) if $journal->can($name);
  no strict 'refs';
  return &{'Bibliotech::CitationSource::Result::Journal::'.$name}(@_) if Bibliotech::CitationSource::Result::Journal->can($name);
  die "cannot handle $name";
}

1;
__END__
