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
use Bibliotech::BibUtils qw(bib2ris);
use Bibliotech::Import::BibTeX;

sub new {
  my $bibtex = pop;
  my $ris = Bibliotech::Import::BibTeX::fix_intermediate_ris(bib2ris($bibtex));
  return Bibliotech::CitationSource::RIS->new($ris);
}

1;
__END__
