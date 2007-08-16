# Copyright 2006 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This file provides all database-level methods, with one class
# representing each table, plus some extra classes.

use strict;

package Bibliotech::Clicks;
use base 'Bibliotech::DBI';

our $DBI_CONNECT  = Bibliotech::Config->get_required('CLICKS', 'DBI_CONNECT');
our $DBI_USERNAME = Bibliotech::Config->get	    ('CLICKS', 'DBI_USERNAME');
our $DBI_PASSWORD = Bibliotech::Config->get	    ('CLICKS', 'DBI_PASSWORD');
__PACKAGE__->connection($DBI_CONNECT, $DBI_USERNAME, $DBI_PASSWORD);

package Bibliotech::Clicks::Log;
use base 'Bibliotech::Clicks';
use URI;
use Net::IP;

__PACKAGE__->columns(Primary => qw/click_id/);
__PACKAGE__->columns(Essential => qw/source_uri dest_uri username ip_addr time/);
__PACKAGE__->has_a(source_uri => 'URI');
__PACKAGE__->has_a(dest_uri => 'URI');
__PACKAGE__->has_a(ip_addr => 'Net::IP');
__PACKAGE__->datetime_column('time', 'before_create');

sub user {
  Bibliotech::User->new(shift->username);
}

sub add {
  shift @_ if $_[0] eq __PACKAGE__;
  my ($source_uri, $dest_uri, $username, $ip_addr) = @_;
  my $entry = __PACKAGE__->insert({source_uri => $source_uri,
				   dest_uri   => $dest_uri,
				   username   => $username,
				   ip_addr    => $ip_addr});
  return;
}

package Bibliotech::Clicks::CGI;
use CGI;
use URI;

sub onclick {
  shift @_ if $_[0] eq __PACKAGE__;
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
  shift @_ if $_[0] eq __PACKAGE__;
  my ($bibliotech, $dest_uri, $new_window) = @_;
  my $location = $bibliotech->location;
  (my $path    = $bibliotech->canonical_path) =~ s|^/||;
  return onclick($location, $location.$path, $dest_uri, $new_window);
}
