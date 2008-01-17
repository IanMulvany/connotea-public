# Copyright 2008 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Import::EndNoteXML class imports EndNote XML

package Bibliotech::Import::EndNoteXML;
use strict;
use base 'Bibliotech::Import';
use File::Temp ();
use Bibliotech::Import::RIS;
use Bibliotech::BibUtils qw(can_endx2ris endx2ris);

sub name {
  'EndNote (XML) [Experimental]';
}

sub version {
  1.0;
}

sub api_version {
  1;
}

sub mime_types {
  ('application/x-bibliographic');
}

sub extensions {
  ('end');
}

sub understands {
  return 0 unless can_endx2ris();
  return $_[1] =~ /<RECORDS>/ ? 1 : 0;
}

sub parse {
  my $self = shift;
  my $ris_import = Bibliotech::Import::RIS->new({bibliotech => $self->bibliotech,
						 doc        => endx2ris($self->doc)});
  return unless $ris_import->parse;
  $self->data($ris_import->data);
  return 1;
}

1;
__END__
