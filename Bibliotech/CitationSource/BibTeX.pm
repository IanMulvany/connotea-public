# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::BibTeX class interprets BibTeX.

package Bibliotech::CitationSource::BibTeX;
use strict;
use Bibliotech::CitationSource::RIS;
use Bibliotech::BibUtils qw(bib2xml xml2ris);
use Bibliotech::Import::BibTeX;

sub new {
  my $bibtex = pop;
  my $mods = bib2xml($bibtex);
  $mods =~ s|&#8217;|__QUOTE__|g;  # bibutils only changes single quotes like this for BibTeX
  my $ris_raw = xml2ris($mods);
  $ris_raw =~ s|__QUOTE__|\'|g;
  my $ris = Bibliotech::Import::BibTeX::fix_intermediate_ris($ris_raw);
  return Bibliotech::CitationSource::RIS->new($ris);
}

1;
__END__
