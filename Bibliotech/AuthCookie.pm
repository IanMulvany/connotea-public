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

  my $uri = do { local $_ = $r->uri;
		 my $location = $r->location;
		 s|^$location|| if $location && $location ne '/';
		 $_; };

  # optional system - HTTP
  if ($uri =~ m{^/+(?:auth|data)}) {
    # /auth is a URI keyword to force an authentication check by HTTP to facilitate RSS readers
    # /data needs to have HTTP authentication to facilitate programatic access
    my ($status, $password) = $r->get_basic_auth_pw;
    return $status unless $status == OK;
    my $username = $r->user;
    my $user = eval { Bibliotech->allow_login($username, $password) };
    return mark_apache_request_for_user($r, $user->user_id, $username, Bibliotech::Util::time())
	if defined $user;
    $r->note_basic_auth_failure;
    return AUTH_REQUIRED;
  }

  if ($uri =~ m|^/+pub|) {
    # /pub is a URI keyword to force the system to NOT read the login cookie
    return NOT_FOUND if $uri =~ m|^/+pub/+data|;  # cheating
    return OK;
  }

  # mandatory system - cookie
  if (my @data = Bibliotech::Cookie::check_cookie_from_apache_request_object($r)) {
    return mark_apache_request_for_user($r, @data);
  }

  return OK;
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

*authen_handler = \*handler;  # described in docs as authen_handler

1;
__END__
