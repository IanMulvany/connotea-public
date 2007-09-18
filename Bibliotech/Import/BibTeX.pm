# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Import::BibTeX class imports BibTeX

package Bibliotech::Import::BibTeX;
use strict;
use base 'Bibliotech::Import';
use File::Temp ();
use Text::Balanced qw(extract_bracketed);
use Data::Dumper;
use Bibliotech::Import::RIS;
use Bibliotech::BibUtils qw(can_bib2ris bib2ris);

sub name {
  'BibTeX [Experimental]';
}

sub version {
  1.0;
}

sub api_version {
  1;
}

sub mime_types {
  ('application/x-bibtex');
}

sub extensions {
  ('bib');
}

sub understands {
  return 0 unless can_bib2ris();
  return $_[1] =~ /^ *\@ *\w+ *\{\S+, *$/m ? 1 : 0;
}

sub split {
  my $self = shift;
  local $_ = shift || $self->doc;
  my $pre = '';
  my @blocks;
  while (/^ *(\@ *\w+ *)(\{.*)\z/sm) {
    my ($code, $entry_plus_remainder) = ($1, $2);
    my $full = $code.$entry_plus_remainder;
    my ($entry, $remainder) = extract_bracketed($entry_plus_remainder, '{}') or last;
    (my $clean_code = $code) =~ s/ //g;
    my $single = $clean_code.$entry."\n";
    if ($clean_code eq '@String') {
      $pre .= $single;
    }
    else {
      push @blocks, $pre.$single;
    }
    substr($_, -length($full), length($full), $remainder);
  }
  return @blocks;
}

sub parse_translated {
  my ($self, $type, $newdoc) = @_;
  my $class = 'Bibliotech::Import::'.$type;
  my $obj = $class->new({bibliotech => $self->bibliotech, doc => $newdoc});
  return unless $obj->parse;
  $self->data($obj->data);
  return 1;
}

sub parse {
  my $self = shift;
  my $ris = join("\n", map { fix_intermediate_ris(bib2ris(fix_incoming_bibtex($_))) } $self->split);
  return $self->parse_translated(RIS => $ris);
}

sub fix_incoming_bibtex {
  local $_ = shift;

  $_ = _rewrite_keywords($_);

  s/adsurl(\s*=\s*{)/url$1/g;
  s/adsnote(\s*=\s*{)/description$1/g;

  # cheat with pmid and asin keywords - force them into doi with
  # markers which will get put in M3 in the RIS and then picked up in
  # the RIS citation source module; although right now bib2ris only
  # handles the first doi line it sees, so only one will get through,
  # but that doesn't seem too bad since they should be all valid
  s/\b(pmid|pubmed)(\s*=\s*{)/doi${2}PMID:/gi;
  s/\b(asin|isbn)(\s*=\s*{)/doi${2}ASIN:/gi;

  return $_;
}

sub _rewrite_keywords {
  my $bibtex = pop;
  my $rewrite_keywords_inner = sub {
    my $keywords = shift;
    return $keywords if $keywords =~ /[,;]/;
    return join(', ', split(/\s+/, $keywords));
  };
  $bibtex =~ s/(keywords\s*=\s*{)([^\}]*)(})/$1.$rewrite_keywords_inner->($2).$3/ge;
  return $bibtex;
}

sub fix_intermediate_ris {
  local $_ = pop;
  # don't call it standard when it has an url, call it electronic
  s/^TY  - STD$/TY  - ELEC/m if /^UR  - ./m;
  # various url fixes
  s/^(UR  - )(.*)$/$1._fix_url($2)/gme;
  return $_;
}

sub _fix_url {
  local $_ = shift;
  # a howPublished field gets changed by bib2xml to another <url> entry
  # and that gets used by xml2ris as the UR line... it usually has a
  # title, url format.. and it gets corrupted; fix:
  s|^.*, \\url(.*)$|$1|;
  # for some reason, bibutils will remove slashes before ampersands in
  # titles etc but not url's which makes parameters in url's not work
  s|\\&|&|g;
  return $_;
}

1;
__END__
