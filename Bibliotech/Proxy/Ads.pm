# Copyright 2006 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::Proxy class translates Ads URL's.

package Bibliotech::Proxy::Ads;

use strict;
use warnings;

use Bibliotech::Proxy;
use base 'Bibliotech::Proxy';

use URI;

sub api_version {
  1;
}

sub name {
  'Ads';
}

sub version {
  '1.1.2.2';
}

sub understands {
  my ($self, $uri) = @_;
  return 0 unless $uri->scheme eq 'http';
  return $uri->host =~ /\.ezp1\.harvard\.edu$/ ? 1 : 0;
}

sub filter {
  my ($self, $current_uri) = @_;
  my $uri = "$current_uri";
  $uri =~ s/\.ezp1\.harvard\.edu//;
  return URI->new($uri);
}

1;
__END__
