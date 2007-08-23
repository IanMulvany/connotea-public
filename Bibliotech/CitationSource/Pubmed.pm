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

sub api_version {
  1;
}

sub name {
  'Pubmed';
}

sub version {
  '2.0';
}

sub understands {
  my ($self, $uri, $content_sub) = @_;

  return 5 if $uri =~ /^\d+$/;  # not a URL but a raw PMID, number only ... return a true but suboptimal score

  my $scheme = $uri->scheme or return 0;
  return 1 if $scheme =~ /^pm(?:id)?$/i;
  return 0 unless $scheme eq 'http';
  
  my $host = $uri->host or return 0;
  return 0 unless $host =~ /^(www|eutils)\.ncbi\.nlm\.nih\.gov(\.proxy\d+\.lib\.umanitoba\.ca)?$/;

  return 1 if $self->understands_id({db     => _db_from_url($uri) || undef,
				     pubmed => _id_from_url($uri) || undef});

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
  while ($content =~ /<dd class="abstract" id="abstract(\d+)">/g) {
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
  return _url_from_pmid('view', 'pubmed', $uri) if $uri =~ /^\d+$/;
  return _url_from_pmid('view', 'pubmed', $uri->opaque) if $uri->scheme =~ /^pm(?:id)?$/i;
  return;
}

sub _url_from_pmid {
  my ($purpose, $db, $id) = @_;
  $db ||= 'pubmed';
  $id =~ s/\%20//g;
  $id =~ s/\D//g;
  my $uri;
  if ($purpose eq 'view') {
    $uri = URI->new('http://www.ncbi.nlm.nih.gov/entrez/query.fcgi');
    $uri->query_param(cmd => 'Retrieve');
    $uri->query_param(db => $db);
    $uri->query_param(dopt => 'Abstract');
    $uri->query_param(list_uids => $id);
  }
  elsif ($purpose eq 'fetch') {
    $uri = URI->new('http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi');
    $uri->query_param(retmode => 'xml');
    $uri->query_param(db => $db);
    $uri->query_param(id => $id);
  }
  return $uri;
}

sub _db_from_url {
  my $uri = shift;
  return $uri->query_param('Db') || $uri->query_param('db');
}

sub _id_from_url {
  my $uri = shift;
  return $uri->query_param('TermToSearch') || $uri->query_param('list_uids');
}

sub citations {
  my ($self, $article_uri, $content_sub) = @_;
  return undef unless $self->understands($article_uri, $content_sub);
  my ($db, $id);
  eval {
    $db = _db_from_url($article_uri) or die "no database parameter (Db or db)\n";
    $id = _id_from_url($article_uri) or die "no PMID parameter (TermToSearch or list_uids)\n";
  };
  my $e = $@;
  die $e if $e =~ /at .* line \d+/;
  if ($e =~ /no PMID parameter/) {
    $e = undef if $id = is_search_page_with_one_result($content_sub);
  }
  $self->errstr($e), return undef if $e;
  return $self->citations_id({db => $db, pubmed => $id});
}

sub citations_id {
  my ($self, $id_hashref) = @_;

  my $io = eval {
    die "do not understand id\'s\n" unless $self->understands_id($id_hashref);
    my $query_uri = _url_from_pmid('fetch', $id_hashref->{db}, $id_hashref->{pubmed});
    my $xml = $self->get($query_uri) or die "XML retrieval failed\n";
    die "Error message from Pubmed server: $1\n" if $xml =~ m|<Error[^>]*>(.*)</Error>|si;
    my $obj = Bio::Biblio::IO->new(-data => $xml, -format => 'pubmedxml') or die "IO object false\n";
    return $obj;
  };
  die $@ if $@ =~ /at .* line \d+/;
  $self->errstr($@), return undef if $@;

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
