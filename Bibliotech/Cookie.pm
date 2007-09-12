# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Cookie class creates cookies.

package Bibliotech::Cookie;
use strict;
use CGI;
use CGI::Cookie;
use Digest::MD5 qw(md5_hex);
use Bibliotech::Config;

our $USER_COOKIE_SECRET = Bibliotech::Config->get_required('USER_COOKIE_SECRET');
our $COOKIESPLIT = ',';
our $HASHSPLIT = ',';

sub check_cookie {
  my $cookie = pop or return;
  my $value  = ref $cookie ? $cookie->value : $cookie;
  my ($user_id, $username, $logintime, $hash_given) = split(/$COOKIESPLIT/o, $value);
  return unless $hash_given;
  my $hash_computed = md5_hex(join($HASHSPLIT, $user_id, $username, $logintime, $USER_COOKIE_SECRET));
  return unless $hash_given eq $hash_computed;
  return wantarray ? ($user_id, $username, $logintime) : [$user_id, $username, $logintime];
}

sub check_cookie_from_cgi_object {
  check_cookie(pop->cookie('bibliotech'));
}

sub check_cookie_from_apache_request_object {
  my $r = pop or return;
  my $cookie_header = $r->headers_in->get('Cookie') or return;
  my %cookies = CGI::Cookie->parse($cookie_header) or return;
  my $cookie = $cookies{'bibliotech'} or return;
  return check_cookie($cookie);
}

sub make_login_cookie {
  my ($self, $location, $secret, $user_id, $username, $logintime) = @_;
  my @values = ($user_id, $username, $logintime);
  my $hash = md5_hex(join($HASHSPLIT, @values, $secret));
  return new CGI::Cookie(-name    => 'bibliotech',
			 -value   => join($COOKIESPLIT, @values, $hash),
			 -path    => $location,
			 -expires => '+1y');
}

sub login_cookie {
  my ($self, $user, $bibliotech) = @_;
  die 'user is not a Bibliotech::User object' unless UNIVERSAL::isa($user, 'Bibliotech::User');
  return $self->make_login_cookie($bibliotech->request->location,
				  $USER_COOKIE_SECRET,
				  $user->user_id,
				  $user->username,
				  time);
}

sub logout_cookie {
  my ($self, $bibliotech) = @_;
  return $self->make_login_cookie($bibliotech->request->location,
				  $USER_COOKIE_SECRET,
				  0,
				  'logout',
				  time);
}

sub login_redirect_cookie {
  my ($self, $uri, $bibliotech) = @_;
  return new CGI::Cookie(-name    => 'bibliotech_redirect',
			 -value   => $uri,
			 -path    => $bibliotech->request->location);
}

sub get_login_redirect_cookie {
  my ($self, $r) = @_;
  if (my $cookie_header = $r->headers_in->get('Cookie')) {
    if (my %cookies = CGI::Cookie->parse($cookie_header)) {
      if (my $cookie = $cookies{'bibliotech_redirect'}) {
	return $cookie->value;
      }
    }
  }
  return undef;
}

sub virgin_cookie {
  my ($self, $r) = @_;
  return new CGI::Cookie(-name    => 'bibliotech_virgin',
			 -value   => 1,
			 -path    => $r->location,
			 -expires => '+24h');
}

sub has_virgin_cookie {
  my $r = pop;
  my $cookie_header = $r->headers_in->get('Cookie') or return;
  my %cookies = CGI::Cookie->parse($cookie_header) or return;
  my $cookie = $cookies{'bibliotech_virgin'} or return;
  return $cookie->value;
}
