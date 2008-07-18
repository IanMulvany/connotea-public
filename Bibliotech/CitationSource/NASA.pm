# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

use strict;
use Bibliotech::CitationSource;

package Bibliotech::CitationSource::NASA;
use base 'Bibliotech::CitationSource';
use URI;
use URI::QueryParam;
use Bibliotech::CitationSource::BibTeX;

our %JOURNAL = (aj           => 'Astronomical Journal',
		araa         => 'Annual Review of Astron and Astrophys',
		apj          => 'Astrophysical Journal',
		apjl         => 'Astrophysical Journal, Letters',
		apjs         => 'Astrophysical Journal, Supplement',
		ao           => 'Applied Optics',
		apss         => 'Astrophysics and Space Science',
		aap          => 'Astronomy and Astrophysics',
		aapr         => 'Astronomy and Astrophysics Reviews',
		aaps         => 'Astronomy and Astrophysics, Supplement',
		azh          => 'Astronomicheskii Zhurnal',
		baas         => 'Bulletin of the AAS',
		jrasc        => 'Journal of the RAS of Canada',
		memras       => 'Memoirs of the RAS',
		mnras        => 'Monthly Notices of the RAS',
		pra          => 'Physical Review A: General Physics',
		prb          => 'Physical Review B: Solid State',
		prc          => 'Physical Review C',
		prd          => 'Physical Review D',
		pre          => 'Physical Review E',
		prl          => 'Physical Review Letters',
		pasp         => 'Publications of the ASP',
		pasj         => 'Publications of the ASJ',
		qjras        => 'Quarterly Journal of the RAS',
		skytel       => 'Sky and Telescope',
		solphys      => 'Solar Physics',
		sovast       => 'Soviet Astronomy',
		ssr          => 'Space Science Reviews',
		zap          => 'Zeitschrift fuer Astrophysik',
		nat          => 'Nature',
		iaucirc      => 'IAU Cirulars',
		aplett       => 'Astrophysics Letters',
		apspr        => 'Astrophysics Space Physics Research',
		bain         => 'Bulletin Astronomical Institute of the Netherlands',
		fcp          => 'Fundamental Cosmic Physics',
		gca          => 'Geochimica Cosmochimica Acta',
		grl          => 'Geophysics Research Letters',
		jcp          => 'Journal of Chemical Physics',
		jgr          => 'Journal of Geophysics Research',
		jqsrt        => 'Journal of Quantitiative Spectroscopy and Radiative Transfer',
		memsai       => 'Mem. Societa Astronomica Italiana',
		nphysa       => 'Nuclear Physics A',
		physrep      => 'Physics Reports',
		physscr      => 'Physica Scripta',
		planss       => 'Planetary Space Science',
		procspie     => 'Proceedings of the SPIE',
		);

sub api_version {
  1;
}

sub name {
  'Smithsonian/NASA ADS';
}

sub cfgname {
  'NASA';
}

sub version {
  '1.2';
}

sub understands {
  my ($self, $uri, $content_sub) = @_;
  return 0 unless $uri->scheme eq 'http';
  return 0 unless $uri->host eq 'adsabs.harvard.edu';
  return 0 unless _bibcode_from_uri_or_content_sub($uri, $content_sub);
  return 1;
}

sub _bibcode_from_uri_or_content_sub {
  my ($uri, $content_sub) = @_;
  return _bibcode_from_uri($uri) || _bibcode_from_content($uri, $content_sub);
}

sub _bibcode_from_uri {
  my $uri = shift;
  return $1 if $uri->path =~ m!^/(?:abs|full)/(.+)!;
  return $uri->query if $uri->path eq '/cgi-bin/bib_query';
  return $uri->query_param('bibcode');
}

sub _bibcode_from_content {
  my ($uri, $content_sub) = @_;
  return _bibcode_from_abstract(scalar($content_sub->())) if $uri->path =~ m!^/doi/!;
  return _bibcode_from_search_page(scalar($content_sub->())) if $uri->path =~ m!^/cgi-bin/nph-(?:abs|basic)_connect$!;
  return;
}

sub _bibcode_from_abstract {
  local $_ = shift;
  my @codes = m/Bibliographic Code:(?:<.*?>)*([\w\.]+)/g;
  return $codes[0] if @codes == 1;
  return;
}

sub _bibcode_from_search_page {
  local $_ = shift;
  my ($codes) = m|<input type="hidden" name="bibcodes" value="([^"]*)">|;
  return unless $codes;
  my @codes = split(/;/, $codes);
  return $codes[0] if @codes == 1;
  return;
}

sub filter {
  my ($self, $uri, $content_sub) = @_;
  if (_bibcode_from_uri($uri)) {
    my $new_uri = $uri;
    foreach ($new_uri->query_param) {
      $new_uri->query_param_delete($_) unless /^(?:bibcode|db_key)$/i;
    }
    return $new_uri unless $new_uri->eq($uri);
    return;
  }
  return URI->new('http://adsabs.harvard.edu/abs/'._bibcode_from_content($uri, $content_sub));
}

sub citations {
  my ($self, $article_uri, $content_sub) = @_;

  my $bibtex;
  eval {
    die "do not understand URI\n" unless $self->understands($article_uri, $content_sub);

    my $bibcode = _bibcode_from_uri_or_content_sub($article_uri, $content_sub);
    my $query_uri = URI->new("http://adsabs.harvard.edu/cgi-bin/nph-bib_query?bibcode=$bibcode&data_type=BIBTEX");

    my $bibtex_raw = $self->get($query_uri);
    $bibtex_raw =~ s/\b(journal *= *{)\\(\w+)(})/$1$JOURNAL{$2}$3/;
    $bibtex = Bibliotech::CitationSource::BibTeX->new($bibtex_raw);

    die "BibTeX obj false\n" unless $bibtex;
    die "BibTeX file contained no data\n" unless $bibtex->has_data;
  };    
  die $@ if $@ =~ /at .* line \d+/;
  $self->errstr($@), return undef if $@;
  return $bibtex->make_result(cfgname(), name())->make_resultlist;
}

1;
__END__
