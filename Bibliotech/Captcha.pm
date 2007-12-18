# Copyright 2006 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Captcha class wraps Authen::Captcha with
# configuration from Bibliotech::Config.

package Bibliotech::Captcha;
use strict;
use base 'Authen::Captcha';
use Digest::MD5 qw(md5_hex);
use Carp;
use File::Spec;
use Bibliotech::Config;

our $DATA_FOLDER     = Bibliotech::Config->get('CAPTCHA', 'DATA_FOLDER')     || '/tmp/captcha/data';
our $OUTPUT_FOLDER   = Bibliotech::Config->get('CAPTCHA', 'OUTPUT_FOLDER')   ||
                       Bibliotech::Config->get('DOCROOT').'/captcha';
our $OUTPUT_LOCATION = Bibliotech::Config->get('CAPTCHA', 'OUTPUT_LOCATION') || '/captcha/';

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(data_folder => $DATA_FOLDER, output_folder => $OUTPUT_FOLDER, @_);
  return bless $self, ref $class || $class;
}

sub img_href {
  my $md5sum = pop;
  return $OUTPUT_LOCATION.$md5sum.'.png';
}

sub is_dup_md5 {
  ref(my $self = shift) or croak "instance variable needed";
  my $md5 = shift;
  my $match_md5 = qr|^\d+::$md5$|;
  my $database_file = File::Spec->catfile($self->data_folder(),'codes.txt');
  open (DATA, "<$database_file")  or die "Can't open File: $database_file\n";
  flock DATA, 1;  # read lock
  my $conflict = eval {
    while (<DATA>) {
      return 1 if /$match_md5/;
    }
    return 0;
  };
  die $@ if $@;
  flock DATA, 8;
  close(DATA);
  return $conflict;
}

# wrap the official version with a loop to skip dup's
# rather than treat them as the official version does
sub generate_random_string {
  ref(my $self = shift) or croak "instance variable needed";
  my $length = shift;
  my ($code, $conflict);
  my $counter = 0;
  do {
    $code = $self->SUPER::generate_random_string($length);
    $conflict = $self->is_dup_md5(md5_hex($code));
  } while ($conflict and ++$counter < 100);
  return $code;
}
