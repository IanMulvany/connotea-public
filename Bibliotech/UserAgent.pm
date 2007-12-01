# Copyright 2006 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This file provides a customized subclass of LWP::UserAgent.

package Bibliotech::UserAgent;
use strict;
use base 'LWPx::ParanoidAgent';
use Bibliotech::Util;

our $SITE_NAME;
sub config_site_name {
  return $SITE_NAME if defined $SITE_NAME;
  eval "use Bibliotech::Config";
  die $@ if $@;
  return $SITE_NAME = Bibliotech::Config->get('SITE_NAME');
}

# create normal object but override sitename
sub new {
  my ($class, %options) = @_;
  my $bibliotech = $options{bibliotech};
  delete $options{bibliotech};
  my $self = $class->SUPER::new(%options);
  my $sitename = defined $bibliotech ? $bibliotech->sitename : config_site_name();
  $self->timeout(180);
  $self->agent($sitename.' ');  # trailing space ensures LWP will add version info
  return $self;
}

# perform request as normal but do content type decoding before releasing to program
sub request {
  my $response = shift->SUPER::request(@_);
  if (defined(my $decoded = Bibliotech::Util::ua_decode_content($response))) {
    $response->content($decoded);
  }
  return $response;
}

# override the user agent used for HTTP::OAI as well
require HTTP::OAI::UserAgent;
@HTTP::OAI::UserAgent::ISA = ('Bibliotech::UserAgent');

1;
__END__
