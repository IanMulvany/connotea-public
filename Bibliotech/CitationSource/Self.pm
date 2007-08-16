# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::Self class does NOT retrieve citation data; it
# recognizes internal URL's, and converts abstract URI references to their
# original URI's, or it simply complains that you shouldn't be bookmarking
# whatever it is you're bookmarking.

package Bibliotech::CitationSource::Self;
use strict;
use base 'Bibliotech::CitationSource';

sub api_version {
  1;
}

sub name {
  'Self';
}

sub version {
  '1.5.2.1';
}

sub match_location_calc {
  my ($uri_o, $location_o, $append_p) = @_;
  return 0 unless defined $location_o;
  my $uri      = "$uri_o";
  my $location = "$location_o";
  my $append   = $append_p || '';
  return 1 if $uri =~ /^\Q$location$append\E/;
  $location =~ s/www\.//;
  return 1 if $uri =~ /^\Q$location$append\E/;
  return 0;
}

sub match_location {
  my ($self, $uri, $append) = @_;
  return match_location_calc($uri, $self->bibliotech->location, $append);
}

sub understands {
  my ($self, $uri) = @_;
  return 0 unless $uri->scheme eq 'http';
  return $self->match_location($uri);
}

sub filter {
  my ($self, $uri) = @_;

  return if $self->match_location($uri, 'wiki');  # allow html wiki links
  
  # if they are adding a simple /uri/xxx link, convert it for them
  if ($self->match_location($uri, 'uri')) {
    if ($uri =~ m|^.*?/uri/([^/]+)|) {
      my $hash = $1;
      if (Bibliotech::Bookmark::is_hash_format($hash)) {
	my ($bookmark) = Bibliotech::Bookmark->search(hash => $hash);
	if ($bookmark) {
	  my $new_uri = $bookmark->uri;
	  return $new_uri if $new_uri;
	}
      }
    }
  }

  $self->errstr('Sorry, you cannot add a URI on this web site '.
		'(if this is a bookmark, please use the copy function instead).');
  return '';  # signal an abort!
}

# there is no citations() method because this module is not designed to get citations
# we are just taking advantage of the filter() method to rewrite local domain URI's

1;
__END__
