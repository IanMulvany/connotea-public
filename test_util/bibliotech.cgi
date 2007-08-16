#!/usr/bin/perl

# Copied from the Urchin source base and modified for Bibliotech
# The Urchin copyright notice:
#
#########################################################################
#Copyright (C) Higher Education Funding Council for England (HEFCE), 2003
#
#This code is licensed under the terms of the GNU General Public License
#(http://www.gnu.org/licenses/gpl.html).
#########################################################################

use strict;

# Apache::Emulator 0.04 uses mod_perl 1.0 stuff so load in mod_perl 2 compatiblity modules..
use Apache2;
use Apache::compat;
# get OK..
use Apache::Const qw(:common);
# now load the emulator...
use Apache::Emulator;
# set the lib path to include the standard place for the modules...
use FindBin;
use lib $FindBin::Bin;
# now load the mod_perl handler...
use Bibliotech::Apache;
use Bibliotech::AuthCookie;
# now bootstrap it...
my %dir_config = ('cgi' => 1);
unless ($ENV{'GATEWAY_INTERFACE'}) {
  $dir_config{'cmdline'} = 1;
  if ($ARGV[0] eq '-X') {
    $ENV{'BIBLIOTECH_DEBUG'} = 1;
    shift @ARGV;
  }
}
$ENV{BIBLIOTECH_PATH} = shift @ARGV;
my $r = new Apache::Emulator (PerlHandler => 'Bibliotech::Apache',
			      PerlAuthenHandler => 'Bibliotech::AuthCookie::authen_handler',
			      PerlSetVar => \%dir_config);
exit ($r->status == OK ? 0 : 1);

package Apache::Emulator::Headers;
use strict;

sub new {
  my ($class, $hash_ref) = @_;
  return bless $hash_ref || {}, ref $class || $class;
}

sub get {
  my ($self, $key) = @_;
  return $self->{$key};
}

sub set {
  my ($self, $key, $value) = @_;
  $self->{$key} = $value;
}

package Apache;
use strict;
use FindBin;

our $FAKE_NOTES;
our $FAKE_HEADERS_OUT;

BEGIN {
  $FAKE_NOTES = {logintime => time};
  $FAKE_HEADERS_OUT = new Apache::Emulator::Headers;
}

sub user {
  $ENV{'REMOTE_USER'};
}

sub filename {
  document_root().$ENV{BIBLIOTECH_PATH};
}

sub document_root {
  $FindBin::Bin.'/html';
}

sub args {
  '';
}

sub get_server_name {
  'nurture.nature.com';
}

sub location {
  '/';
}

sub notes {
  $FAKE_NOTES;
}

sub meets_conditions {
  OK;  # effectively no
}

sub set_last_modified {
  # NOOP
}

sub headers_out {
  $FAKE_HEADERS_OUT;
}
