# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::AuthCookie class provides cookie-based user
# authentication.

package Bibliotech::AuthCookie;
use strict;
use Bibliotech::ApacheProper;
use CGI::Cookie;
use Digest::MD5 qw(md5_hex);
use Bibliotech;
use Bibliotech::Const;
use Bibliotech::Util;
use Bibliotech::Config;
use Bibliotech::Cookie;

our $SERVICE_PAUSED     = Bibliotech::Config->get('SERVICE_PAUSED');
our $USER_COOKIE_SECRET = Bibliotech::Config->get_required('USER_COOKIE_SECRET');
our $COOKIESPLIT 	= $Bibliotech::Cookie::COOKIESPLIT;  # not in config
our $HASHSPLIT   	= $Bibliotech::Cookie::HASHSPLIT;    # not in config

sub handler {
  my ($r) = @_;

  # never prevent access to static files
  my $staticfile = $r->filename.$r->path_info;
  return OK if -e $staticfile and -f $staticfile;

  if (!$r->is_initial_req) {
    return OK if $SERVICE_PAUSED;  # to allow ErrorDocument (but static file check above is probably sufficient)
    return DECLINED;
  }

  # optional system - HTTP
  my $uri = $r->uri;
  my $location = $r->location;
  $uri =~ s|^$location|| if $location && $location ne '/';
  if ($uri =~ m{^/+(auth|data)}) {
    my ($status, $password) = $r->get_basic_auth_pw;
    return $status unless $status == OK;
    my $username = $r->user;
    my $user;
    eval {
      $user = Bibliotech->allow_login($username, $password);
    };
    return mark_apache_request_for_user($r, $user->user_id, $username, Bibliotech::Util::time())
	if defined $user;
    $r->note_basic_auth_failure;
    return AUTH_REQUIRED;
  }

  # mandatory system - cookie
  if (my @data = Bibliotech::Cookie::check_cookie_from_apache_request_object($r)) {
    return mark_apache_request_for_user($r, @data);
  }

  if ($uri =~ m|^/+data|) {
    $r->note_basic_auth_failure;
    return AUTH_REQUIRED;
  }

  return OK;
}

# legacy
sub authen_handler {
  handler(@_);
}

sub mark_apache_request_for_user {
  my ($r, $user_id, $username, $logintime) = @_;
  my $notes = $r->notes;
  $notes->{'logintime'} = $logintime;
  if ($user_id > 0) {
    $r->user($user_id);
    $notes->{'username'} = $username;
  }
  return OK;
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

# legacy
sub make_login_cookie {
  my $self = shift;
  return Bibliotech::Cookie->make_login_cookie(@_);
}

# legacy
sub login_cookie {
  my $self = shift;
  return Bibliotech::Cookie->login_cookie(@_);
}

# legacy
sub logout_cookie {
  my $self = shift;
  return Bibliotech::Cookie->logout_cookie(@_);
}

# legacy
sub login_redirect_cookie {
  my $self = shift;
  return Bibliotech::Cookie->login_redirect_cookie(@_);
}

1;
__END__
