# Copyright 2008 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::Atypon class retrieves citation data
# for articles on Atypon powered web sites.
#
# Supports at least:
#   www.aluka.org
#   www.joponline.org
#   www.anthrosource.net
#   cerealchemistry.aaccnet.org
#   pubs.acs.org
#   apsjournals.apsnet.org
#   www.jbmronline.org
#   www.amstat.org
#   avmajournals.avma.org
#   arjournals.annualreviews.org
#   www.bioone.org
#   www.blackwell-synergy.com
#   www.cfapubs.org
#   www.cshl-symposium.org
#   www.crossref.org
#   www.eupjournals.com
#   www.expertopin.com
#   www.future-drugs.com
#   www.futuremedicine.com
#   inscribe.iupress.org
#   www.ieee.org
#   www.thejns.org
#   www.jstor.org
#   www.leaonline.com
#   www.liebertonline.com
#   www.mitpressjournals.org
#   www.mlajournals.org
#   publications.epress.monash.edu
#   www.morganclaypool.com
#   health.salempress.com
#   caliber.ucpress.net
#   www.journals.uchicago.edu
#   www.degruyter.com

use strict;
use Bibliotech::CitationSource;
use Bibliotech::CitationSource::NPG;

package Bibliotech::CitationSource::Atypon;
use base 'Bibliotech::CitationSource';
use URI;
use URI::QueryParam;
use DateTime;

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
  return 0 unless m|<a href="http://www.atypon.com| or       # match "Technology Partner" banner
                  m|<a href="/action/showCitFormats\?doi=|;  # match "Download to Citation Mgr" link
  return 3;
}

sub _doi_from_uri {
  my $uri = shift;
  $uri->path =~ m|/doi(?:/[a-z]+)?/(10\.\w+/[^/]+)| and return $1;
  local $_ = $uri->query_param('doi') and return $_;
  return;
}

sub _query_uri {
  my ($host, $doi) = @_;
  my $q = URI->new('http://'.$host.'/action/downloadCitation');
  $q->query_param(doi     => $doi);
  $q->query_param(include => 'cit');
  $q->query_param(format  => 'refman');
  $q->query_param(submit  => 'Download');
  return $q;
}

sub _fix_date {
  local $_ = shift;
  my ($year, $month, $day) = m|^(\d+)/(\d+)/(\d+)$|;
  return $_ if $day <= 31;
  # fix bug where day is day-of-year (1-365)
  return DateTime->from_day_of_year(year => $year, day_of_year => $day)->ymd;
}

sub _fix_ris_date {
  local $_ = shift;
  s|^(Y1  - )(\d+/\d+/\d+)|$1._fix_date($2)|em;
  return $_;
}

sub citations {
  my ($self, $uri, $content_sub) = @_;
  my $ris = eval {
    die "do not understand URI\n" unless $self->understands($uri, $content_sub);
    my $doi = _doi_from_uri($uri) or die "no DOI\n";
    my ($res, $ris_raw) = $self->get(_query_uri($uri->host, $doi));
    $res->is_success or 'trying to get RIS: '.$res->status_line."\n";
    my $ris = Bibliotech::CitationSource::NPG::RIS->new(_fix_ris_date($ris_raw)) or die "no RIS object\n";
    $ris->has_data or die "RIS file contained no data\n";
    return $ris;
  };
  die $@ if $@ =~ /at .* line \d+/;
  $self->errstr($@), return undef if $@;
  return $ris->make_result->make_resultlist('Atypon', 'Atypon powered site at '.$uri->host);
}

1;
__END__
