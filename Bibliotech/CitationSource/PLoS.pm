# Copyright 2005 Bartosz Telenczuk
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::PLoS class retrieves citation data for articles
# on plosjournals.org.

use strict;
use Bibliotech::CitationSource;
use Bibliotech::CitationSource::NPG;

package Bibliotech::CitationSource::PLoS;
use base 'Bibliotech::CitationSource';
use URI;
use URI::QueryParam;

sub api_version {
  1;
}

sub name {
  'Public Library of Science';
}

sub cfgname {
  'PLoS';
}

sub version {
  '0.1';
}

sub understands {
  my ($self, $uri) = @_;
  return 0 unless $uri->scheme =~ /^http$/i;
  return 0 unless $uri->host =~ /^\w+.plosjournals.org$/;
  return 1 if $uri->path =~ m!/pdf/\d{2}\.\d{4}_.+?-[LS]\.pdf$!;
  return 0 unless $uri->query;
  return 1 if $uri->query =~ m/get-document/;
  return 0;
}

sub citations {
  my ($self, $article_uri) = @_;

  my $ris;
  
  eval {
    die "do not understand URI\n" unless $self->understands($article_uri);

    my $doi;
    if($article_uri->query_param('doi')) {
	$doi = $article_uri->query_param('doi');
    }
    if($article_uri->path =~ m!/pdf/(\d{2}\.\d{4})_(.+?)-[LS]\.pdf$!i) {
	$doi = $1 . '/' . $2;
    }

    die "no doi\n" unless $doi;
    
    my $query_uri = 'http://' . $article_uri->host . '/perlserv/?request=download-citation&t=refman&doi=' .$doi;

    my $ris_raw = $self->get($query_uri);
    $ris = new Bibliotech::CitationSource::NPG::RIS ($ris_raw);

    die "RIS obj false\n" unless $ris;
    die "RIS file contained no data\n" unless $ris->has_data;
    $ris->{M3}=$doi;
    #$ris->{'doi'}=$doi;
    #$ris->{'misc3'}=$doi;
  };    
  die $@ if $@ =~ /at .* line \d+/;
  $self->errstr($@), return undef if $@;
  return bless [bless $ris, 'Bibliotech::CitationSource::PLoS::Result'], 'Bibliotech::CitationSource::ResultList';
}

package Bibliotech::CitationSource::PLoS::Result;
use base ('Bibliotech::CitationSource::NPG::RIS', 'Bibliotech::CitationSource::Result');
use HTML::Entities;
use Encode;

sub type {
  'PLoS';
}

sub source {
  'PLoS RIS file from www.plosjournals.org';
}

sub identifiers {
  {doi => shift->doi};
}

sub title {
  my $self = shift;
  my $article_title = decode_entities($self->SUPER::title) or die("Error!");
  return $article_title;
}

sub page {
  shift->collect(qw/starting_page/);
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
  my @authors = map(Bibliotech::CitationSource::PLoS::Result::Author->new($_), ref $authors ? @{$authors} : $authors);
  bless \@authors, 'Bibliotech::CitationSource::Result::AuthorList';
}

sub journal {
  my ($self) = @_;
  return Bibliotech::CitationSource::PLoS::Result::Journal->new($self->justone('journal'),
								$self->justone('journal_abbr'),
								$self->justone('issn'));
}

sub doi     { shift->justone('misc3'); }

package Bibliotech::CitationSource::PLoS::Result::Author;
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

package Bibliotech::CitationSource::PLoS::Result::Journal;
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
