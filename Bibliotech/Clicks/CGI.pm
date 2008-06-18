# Copyright 2008 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This file provides all database-level methods, with one class
# representing each table, plus some extra classes.

package Bibliotech::Clicks::CGI;
use strict;
use CGI;
use URI;

sub onclick {
  shift @_ if !ref($_[0]) and $_[0] eq __PACKAGE__;
  my ($location, $source_uri, $dest_uri, $new_window) = @_;
  my $src    = CGI::escape(URI->new($source_uri)->as_string);
  my $dest   = CGI::escape(URI->new($dest_uri)->as_string);
  my $scheme = $location->scheme;
  (my $rest  = "$location") =~ s|^\Q$scheme\E||;
  my $script = "\'$scheme\'+\'${rest}click?src=${src}&dest=${dest}\'";
  return "this.href=${script}; return true;" unless $new_window;
  #return "window.location=${script}; return false;" unless $new_window;
  return "window.open(${script},\'\',\'\'); return false;";
}

sub onclick_bibliotech {
  shift @_ if !ref($_[0]) and $_[0] eq __PACKAGE__;
  my ($bibliotech, $dest_uri, $new_window) = @_;
  my $location = $bibliotech->location;
  (my $path    = $bibliotech->canonical_path) =~ s|^/||;
  return onclick($location, $location.$path, $dest_uri, $new_window);
}

1;
__END__
