# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::Tracker class provides output to
# track marketing ads.

package Bibliotech::Component::Tracker;
use strict;
use base 'Bibliotech::Component';

sub last_updated_basis {
  'PID';
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;
  my $bibliotech = $self->bibliotech;
  my $cgi = $bibliotech->cgi;

  my $o = '';

  unless (defined $bibliotech->user) {
    (my $path = $bibliotech->canonical_path) =~ s|/|_|g;
    my $options = $self->options;
    unless ($options->{registered}) {
      $o = "<!-- ***  CLICK TRACKING CODE 3.0 *** -->\n";
      # obsolete tracker - script removed
      $o .= "<!-- ^^^ CLICK TRACKING CODE 3.0 ^^^ -->\n";
    }
    else {
      $o .= "<!-- *** ACTION TRACKING CODE 3.0 *** -->\n";
      # obsolete tracker - script removed
      $o .= "<!-- ^^^ ACTION TRACKING CODE 3.0 ^^^ -->\n";
    }
  }

  return Bibliotech::Page::HTML_Content->simple($o);
}

1;
__END__
