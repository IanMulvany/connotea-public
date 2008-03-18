# Copyright 2008 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::Atypon class retrieves citation data
# for articles on Atypon powered web sites.

use strict;
use Bibliotech::CitationSource;
use Bibliotech::CitationSource::NPG;

package Bibliotech::CitationSource::Atypon;
use base 'Bibliotech::CitationSource';
use URI;
use URI::QueryParam;

sub api_version {
  1;
}

sub name {
  'Atypon';
}

sub understands {
  my ($self, $uri, $content_sub) = @_;
  return 0 unless $uri->scheme eq 'http';
  return 0 unless _doi_from_uri($uri);
  local $_ = $self->content_or_set_warnstr($content_sub, ['text/html', 'application/xhtml+xml']) or return 0;
  m|<a href="http://www.atypon.com| or return 0;  # match "Technology Partner" banner
  return 3;
}

sub _doi_from_uri {
  my $uri = shift;
  $uri->path =~ m|/doi(?:/[a-z]+)?/(10\.\w+/[^/]+)| and return $1;
  local $_ = $uri->query_param('doi') and return $_;
  return;
}

sub citations {
  my ($self, $uri, $content_sub) = @_;
  my $ris = eval {
    die "do not understand URI\n" unless $self->understands($uri, $content_sub);
    my $doi = _doi_from_uri($uri) or die "no DOI\n";
    my $q = URI->new('http://'.$uri->host.'/action/downloadCitation');
    $q->query_param(doi     => $doi);
    $q->query_param(include => 'cit');
    $q->query_param(format  => 'refman');
    $q->query_param(submit  => 'Download');
    my ($res, $ris_raw) = $self->get($q);
    $res->is_success or 'trying to get RIS: '.$res->status_line."\n";
    my $ris = Bibliotech::CitationSource::NPG::RIS->new($ris_raw) or die "no RIS object\n";
    $ris->has_data or die "RIS file contained no data\n";
    return $ris;
  };
  die $@ if $@ =~ /at .* line \d+/;
  $self->errstr($@), return undef if $@;
  return $ris->make_result->make_resultlist('Atypon', 'Atypon powered site at '.$uri->host);
}

1;
__END__
