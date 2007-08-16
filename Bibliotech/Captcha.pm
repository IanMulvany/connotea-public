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
use Bibliotech::Config;

our $DATA_FOLDER     = Bibliotech::Config->get('CAPTCHA', 'DATA_FOLDER')     || '/tmp/captcha/data';
our $OUTPUT_FOLDER   = Bibliotech::Config->get('CAPTCHA', 'OUTPUT_FOLDER')   ||
                       Bibliotech::Config->get('DOCROOT').'/captcha';
our $OUTPUT_LOCATION = Bibliotech::Config->get('CAPTCHA', 'OUTPUT_LOCATION') || '/captcha/';

sub new {
  my $class = shift;
  my $self  = Authen::Captcha->new(data_folder => $DATA_FOLDER, output_folder => $OUTPUT_FOLDER);
  return bless $self, $class;
}

sub img_href {
  my $md5sum = pop;
  return $OUTPUT_LOCATION.$md5sum.'.png';
}
