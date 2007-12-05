# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::LoginForm class provides a login form.

package Bibliotech::Component::LoginForm;
use strict;
use base 'Bibliotech::Component';
use Bibliotech::Cookie;

sub last_updated_basis {
  ('LOGIN');
}

sub _cookie_setter {
  my $r   = shift;
  my $out = $r->err_headers_out;
  return sub { $out->add('Set-Cookie' => shift); };
}

# called by other modules as a standard login tool as well
sub set_cookie {
  my ($self, $user, $bibliotech, $set_virgin_login) = @_;
  my $r = $bibliotech->request;
  my $add = _cookie_setter($r);
  $add->(Bibliotech::Cookie->login_cookie($user, $bibliotech));
  $add->(Bibliotech::Cookie->virgin_cookie($r)) if $set_virgin_login;
  return ($user, $bibliotech);
}

sub do_reset_redirect {
  my ($self, $user, $bibliotech) = @_;
  my $r = $bibliotech->request;
  my $add = _cookie_setter($r);
  my $redirect_uri;
  if ($redirect_uri = $bibliotech->cgi->param('dest') || Bibliotech::Cookie->get_login_redirect_cookie($r)) {
    $redirect_uri =~ s/_AMP_/&/g;
    $add->(Bibliotech::Cookie->login_redirect_cookie('', $bibliotech));  # cancel redirect
  }
  else {
    $redirect_uri = $bibliotech->location.'user/'.$user->username;
  }
  return $redirect_uri;
}

sub do_login_and_return_location {
  my ($self, $user, $bibliotech) = @_;
  return $self->do_reset_redirect($self->set_cookie($user, $bibliotech));
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $bibliotech = $self->bibliotech;
  my $cgi        = $bibliotech->cgi;

  my $validationmsg;
  if (lc($cgi->param('button')) eq 'login') {
    my $user = eval { $bibliotech->allow_login($cgi->param('username') || undef, $cgi->param('password') || undef); };
    if (my $e = $@) {
      die $e if $e =~ / at .* line /;
      $validationmsg = $self->validation_exception($e =~ /(?:username|account)/i ? 'username' : 'password', $e);
      $cgi->Delete('password');  # do not redisplay on form
    }
    else {
      die 'Location: '.$self->do_login_and_return_location($user, $bibliotech)."\n";
    }
  }

  my $o = $self->tt('complogin', undef, $validationmsg);

  my $javascript_first_empty = $self->firstempty($cgi, 'login', qw/username password/);

  return Bibliotech::Page::HTML_Content->new({html_parts => {main => $o},
					      javascript_onload => ($main ? $javascript_first_empty : undef)});
}

1;
__END__
