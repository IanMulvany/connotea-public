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
  '1.1.2.2';
}

sub understands {
  my ($self, $uri) = @_;
  return 0 unless $uri->scheme eq 'http';
  return 0 unless $uri->host eq 'adsabs.harvard.edu';
 
  return 0 unless $self->bibcode($uri);
  return 1;
}

sub filter {
  my ($self, $uri) = @_;
  my $new_uri = $uri;
  foreach ($new_uri->query_param) {
    $new_uri->query_param_delete($_) unless /(?:bibcode|db_key)/i;
  }
  return $new_uri unless $new_uri->eq($uri);
  return;
}

sub citations {
  my ($self, $article_uri) = @_;

  my $bibtex;
  eval {
    die "do not understand URI\n" unless $self->understands($article_uri);

    my $bibcode = $self->bibcode($article_uri);
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

sub bibcode {
    my ($self, $uri) = @_;
    if ($uri->path =~ m!^/abs/(.+)!) {
	return $1;
    }
    return $uri->query_param('bibcode');
}

1;
__END__
