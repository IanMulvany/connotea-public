# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::Infobar class provides an information bar.

package Bibliotech::Component::Infobar;
use strict;
use base 'Bibliotech::Component';
use Bibliotech::DBI;
use IO::File;

sub last_updated_basis {
  ('DBI', 'LOGIN', shift->bibliotech->docroot.'menu');
}

sub html_content {
  my ($self, $class, $verbose) = @_;
  my $bibliotech = $self->bibliotech;
  my $user_id = $bibliotech->request->user;

  my $cached = $self->memcache_check(class => __PACKAGE__, method => 'html_content', user => $user_id || 'visitor');
  return $cached if defined $cached;

  my $user = $bibliotech->user;
  my $username = $user ? $user->username : undef;
  my $popup = $bibliotech->command->is_popup;
  my $cgi = $bibliotech->cgi;

  my $menutab = $bibliotech->docroot.'menu';
  my $fh = new IO::File ($menutab) or die "cannot open $menutab: $!";
  my @menu;
  while (<$fh>) {
    chomp;
    next if /^$/ or /^\#/;
    my ($type, $label, $uri_part) = split(/\s*\:\s*/);
    if (($type eq 'user' and $user_id) or ($type eq 'visitor' and !$user_id) or $type eq 'all') {
      push @menu, [$type, $label, $uri_part];
    }
  }
  $fh->close;

  my $menu = join(' | ', map($cgi->a({href => $bibliotech->location.$_->[2],
				      $popup ? (target => '_blank') : (),
				      class => 'nav'}, $_->[1]),
			     @menu));

  return $self->memcache_save(Bibliotech::Page::HTML_Content->simple($menu));
}

1;
__END__
