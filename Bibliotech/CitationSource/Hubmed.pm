# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::Hubmed class retrieves citation data for articles
# in Hubmed.

use strict;
use Bibliotech::CitationSource;
use Bio::Biblio::IO;

package Bibliotech::CitationSource::Hubmed;
use base 'Bibliotech::CitationSource';
use URI;
use URI::QueryParam;

sub api_version {
  1;
}

sub name {
  'Hubmed';
}

sub version {
  '1.3';
}

sub understands {
  my ($self, $uri) = @_;
  return 0 unless $uri->scheme eq 'http';
  return $uri->host eq 'www.hubmed.org' ? 1 : 0;
}

sub citations {
  my ($self, $article_uri) = @_;

  my $io;
  eval {
    die "do not understand URI\n" unless $self->understands($article_uri);

    my $query_uri = new URI ('http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?retmode=xml');
    my ($id) = ($article_uri =~ m!uids=(\d+)!);
    $id or die "no uids parameter\n";
    $query_uri->query_param(db => 'pubmed');
    $query_uri->query_param(id => $id);

    my $xml = $self->get($query_uri) or die "XML retrieval failed\n";
    $io = new Bio::Biblio::IO (-data => $xml, -format => 'pubmedxml') or die "IO object false\n";
  };
  die $@ if $@ =~ /at .* line \d+/;
  $self->errstr($@), return undef if $@;

  # we cannot simply rebless as I'd prefer because Bioperl uses child classes
  return Bibliotech::CitationSource::Pubmed::ResultList->new ($io);
}

1;
__END__
