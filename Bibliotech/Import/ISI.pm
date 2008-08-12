# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Import::ISI class provides an import interface for
# ISI Web of Knowledge files

package Bibliotech::Import::ISI;
use strict;
use base 'Bibliotech::Import';
use File::Temp ();
use Bibliotech::Import::RIS;
use Bibliotech::BibUtils qw(can_isi2ris isi2ris);

sub name {
  'ISI Web of Knowledge';
}

sub version {
  1.0;
}

sub api_version {
  1;
}

sub mime_types {
  ('text/plain');
}

sub extensions {
  ('txt');
}

sub understands {
  return 0 unless can_isi2ris();
  return $_[1] =~ /^PT.*?ER/sm ? 1 : 0;
}

sub parse {
  my $self = shift;
  my $ris_import = Bibliotech::Import::RIS->new({bibliotech => $self->bibliotech, doc => isi2ris($self->doc)});
  return unless $ris_import->parse;
  $self->data($ris_import->data);
  return 1;
}

1;
__END__
