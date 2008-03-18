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
use Bibliotech::Config;

our $SITE_NAME 	= Bibliotech::Config->get('SITE_NAME');
our $STRING    	= Bibliotech::Config->get('AGENT', 'STRING');
our $TIMEOUT   	= Bibliotech::Config->get('AGENT', 'TIMEOUT') || 180;
our $WHITE_LIST = Bibliotech::Config->get('AGENT', 'WHITE_LIST') || [];
our $BLACK_LIST = Bibliotech::Config->get('AGENT', 'BLACK_LIST') || [];

sub _make_qr {
  local $_ = shift;
  /^((\d+\.){1,3})$/ and return qr/^$1/;
  return $_;
}

sub _make_qrs {
  map { ref($_) ? $_ : _make_qr($_) } @_;
}

# create normal object but override sitename
sub new {
  my ($class, %options) = @_;
  my $bibliotech = $options{bibliotech};
  delete $options{bibliotech};
  my $self = $class->SUPER::new(%options);
  my $sitename = defined $bibliotech ? $bibliotech->sitename : $SITE_NAME;
  $self->timeout($TIMEOUT);
  $self->agent($STRING || $sitename.' ');  # trailing space ensures LWP will add version info
  $self->blocked_hosts(_make_qrs(@{$BLACK_LIST}))     if $BLACK_LIST and @{$BLACK_LIST};
  $self->whitelisted_hosts(_make_qrs(@{$WHITE_LIST})) if $WHITE_LIST and @{$WHITE_LIST};
  $self->cookie_jar({});
  return $self;
}

# LWP::UserAgent handles _foreign gracefully but LWPx::ParanoidAgent
# doesn't - although it is a subclass so just pass it back
sub request_handle_foreign {
  my ($self, $req, $arg, $size, $previous) = @_;
  return LWP::UserAgent::request($self, $req, $arg, $size, $previous)
      if UNIVERSAL::isa($req->uri, 'URI::_foreign');
  return $self->SUPER::request($req, $arg, $size, $previous);
}

# perform request as normal but afterwards do content type decoding
sub request {
  my ($self, $req, $arg, $size, $previous) = @_;
  my $response = $self->request_handle_foreign($req, $arg, $size, $previous);
  if (defined(my $decoded = Bibliotech::Util::ua_decode_content($response))) {
    $response->content($decoded);
  }
  return $response;
}

sub system_hosts_file {
  open HOSTS, '</etc/hosts' or die 'unable to open /etc/hosts: '.$!;
  my @hosts = <HOSTS>;
  close HOSTS;
  return @hosts;
}

# look in /etc/hosts
sub _resolve {
  my ($self, $host, $request, $timeout, $depth) = @_;
  unless ($host =~ /^\d+\.\d+\.\d+\.\d+$/) {
    foreach (system_hosts_file()) {
      if (/^(\d+\.\d+\.\d+\.\d+)(\s+[\w\.]+)+$/) {
	my ($ip, @names) = ($1, grep { $_ } split(/\s+/, $2));
	if (grep { $host eq $_ } @names) {
	  return $self->SUPER::_resolve($ip, $request, $timeout, $depth);
	}
      }
    }
  }
  return $self->SUPER::_resolve($host, $request, $timeout, $depth);
}

# override the user agent used for HTTP::OAI as well
require HTTP::OAI::UserAgent;
@HTTP::OAI::UserAgent::ISA = ('Bibliotech::UserAgent');

1;
__END__
