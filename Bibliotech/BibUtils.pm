# Copyright 2006 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#

# The Bibliotech::BibUtils class provides helper routines for
# the bibutils library:
# http://www.scripps.edu/~cdputnam/software/bibutils/

package Bibliotech::BibUtils;
use strict;
require Exporter;
use IPC::Run qw(run);
use List::MoreUtils qw(all);
use Bibliotech::Config;

our @EXPORT_OK = qw(can_all
		    can_bib2xml   bib2xml
		    can_copac2xml copac2xml
		    can_end2xml   end2xml
		    can_isi2xml   isi2xml
		    can_med2xml   med2xml
		    can_modsclean modsclean
		    can_ris2xml   ris2xml
		    can_xml2bib   xml2bib
		    can_xml2end   xml2end
		    can_xml2ris   xml2ris
		    can_xml2word  xml2word
		    can_bib2end   bib2end
		    can_bib2ris   bib2ris
		    can_end2bib   end2bib
		    can_end2ris   end2ris
		    can_ris2bib   ris2bib
		    can_ris2end   ris2end
		    can_ris2word  ris2word
		    can_copac2bib copac2bib
		    can_copac2end copac2end
		    can_copac2ris copac2ris
		    can_isi2bib   isi2bib
		    can_isi2end   isi2end
		    can_isi2ris   isi2ris
		    can_med2bib   med2bib
		    can_med2end   med2end
		    can_med2ris   med2ris
		    );

our $BIBUTILS_PATH = Bibliotech::Config->get('BIBUTILS_PATH') || '/usr/local/bin/bibutils';

sub bibutils_bin {
  $BIBUTILS_PATH.shift;
}

sub bibutils_can {
  my $path = bibutils_bin(shift);
  return -e $path && -x $path;
}

sub bibutils_run {
  my ($cmd, $in_orig) = @_;
  my @cmd = (bibutils_bin($cmd));
  my $in  = $in_orig;
  my $out = '';
  my $err = '';
  run \@cmd, \$in, \$out, \$err or die "@cmd: $?";
  return $out;
}

sub can_bib2xml   { bibutils_can('bib2xml')          }
sub bib2xml       { bibutils_run('bib2xml'   => pop) }
sub can_copac2xml { bibutils_can('copac2xml')        }
sub copac2xml     { bibutils_run('copac2xml' => pop) }
sub can_end2xml   { bibutils_can('end2xml')          }
sub end2xml       { bibutils_run('end2xml'   => pop) }
sub can_isi2xml   { bibutils_can('isi2xml')          }
sub isi2xml       { bibutils_run('isi2xml'   => pop) }
sub can_med2xml   { bibutils_can('med2xml')          }
sub med2xml       { bibutils_run('med2xml'   => pop) }
sub can_modsclean { bibutils_can('modsclean')        }
sub modsclean     { bibutils_run('modsclean' => pop) }
sub can_ris2xml   { bibutils_can('ris2xml')          }
sub ris2xml       { bibutils_run('ris2xml'   => pop) }
sub can_xml2bib   { bibutils_can('xml2bib')          }
sub xml2bib       { bibutils_run('xml2bib'   => pop) }
sub can_xml2end   { bibutils_can('xml2end')          }
sub xml2end       { bibutils_run('xml2end'   => pop) }
sub can_xml2ris   { bibutils_can('xml2ris')          }
sub xml2ris       { bibutils_run('xml2ris'   => pop) }
sub can_xml2word  { bibutils_can('xml2word')         }
sub xml2word      { bibutils_run('xml2word'  => pop) }

sub can_all { all { $_ } (can_bib2xml(),
			  can_copac2xml(),
			  can_end2xml(),
			  can_isi2xml(),
			  can_med2xml(),
			  can_modsclean(),
			  can_ris2xml(),
			  can_xml2bib(),
			  can_xml2end(),
			  can_xml2ris(),
			  can_xml2word(),
			  );
	    }

# combinations based on the building blocks above
sub can_bib2end   { can_bib2xml() && can_xml2end() }
sub bib2end       { xml2end(bib2xml(pop)) }
sub can_bib2ris   { can_bib2xml() && can_xml2ris() }
sub bib2ris       { xml2ris(bib2xml(pop)) }
sub can_end2bib   { can_end2xml() && can_xml2bib() }
sub end2bib       { xml2bib(end2xml(pop)) }
sub can_end2ris   { can_end2xml() && can_xml2ris() }
sub end2ris       { xml2ris(end2xml(pop)) }
sub can_ris2bib   { can_ris2xml() && can_xml2bib() }
sub ris2bib       { xml2bib(ris2xml(pop)) }
sub can_ris2end   { can_ris2xml() && can_xml2end() }
sub ris2end       { xml2end(ris2xml(pop)) }
sub can_ris2word  { can_ris2xml() && can_xml2word() }
sub ris2word      { xml2word(ris2xml(pop)) }
sub can_copac2bib { can_copac2xml() && can_xml2bib() }
sub copac2bib     { xml2bib(copac2xml(pop)) }
sub can_copac2end { can_copac2xml() && can_xml2end() }
sub copac2end     { xml2end(copac2xml(pop)) }
sub can_copac2ris { can_copac2xml() && can_xml2ris() }
sub copac2ris     { xml2ris(copac2xml(pop)) }
sub can_isi2bib   { can_isi2xml() && can_xml2bib() }
sub isi2bib       { xml2bib(isi2xml(pop)) }
sub can_isi2end   { can_isi2xml() && can_xml2end() }
sub isi2end       { xml2end(isi2xml(pop)) }
sub can_isi2ris   { can_isi2xml() && can_xml2ris() }
sub isi2ris       { xml2ris(isi2xml(pop)) }
sub can_med2bib   { can_med2xml() && can_xml2bib() }
sub med2bib       { xml2bib(med2xml(pop)) }
sub can_med2end   { can_med2xml() && can_xml2end() }
sub med2end       { xml2end(med2xml(pop)) }
sub can_med2ris   { can_med2xml() && can_xml2ris() }
sub med2ris       { xml2ris(med2xml(pop)) }
