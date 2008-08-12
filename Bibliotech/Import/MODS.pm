# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Import::MODS class provides an import interface for
# MODS XML (see http://www.loc.gov/standards/mods/) files

package Bibliotech::Import::MODS;
use strict;
use base 'Bibliotech::Import';
use File::Temp ();
use Bibliotech::Import::RIS;
use Bibliotech::BibUtils qw(can_modsclean modsclean can_xml2ris xml2ris);

sub name {
  'MODS';
}

sub version {
  1.0;
}

sub api_version {
  1;
}

sub mime_types {
  ('application/xml', 'application/xml+mods');
}

sub extensions {
  ('xml', 'mods');
}

sub understands {
  return 0 unless can_modsclean() && can_xml2ris();
  return $_[1] =~ m!xmlns(:.+?)?\s*=\s*"http://www\.loc\.gov/mods/v3"!sm ? 1 : 0;
}

sub parse {
  my $self = shift;
  my $ris_import = Bibliotech::Import::RIS->new({bibliotech => $self->bibliotech,
						 doc        => xml2ris(modsclean($self->doc))});
  return unless $ris_import->parse;
  $self->data($ris_import->data);
  return 1;
}

1;
__END__


