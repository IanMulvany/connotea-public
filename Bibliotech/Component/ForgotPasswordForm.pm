# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::VerifyForm class provides output to show when a
# new user is verified (gets their email and clicks the link).

package Bibliotech::Component::ForgotPasswordForm;
use strict;
use base 'Bibliotech::Component';
use Digest::MD5 qw(md5_hex);
use Bibliotech::Config;
use Bibliotech::Util;
use Bibliotech::Component::LoginForm;
use Bibliotech::Component::RegisterForm;

our $FORGOTTEN_PASSWORD_SECRET = Bibliotech::Config->get('FORGOTTEN_PASSWORD_SECRET')
    or die 'no forgotten password secret defined';
our $HASHSPLIT = '/';

sub last_updated_basis {
  'NOW';
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $bibliotech = $self->bibliotech;
  my $cgi        = $bibliotech->cgi;
  my $location   = $bibliotech->location;
  my $validationmsg;

  if (my $email = $cgi->param('email')) {
    eval {

      my ($user) = Bibliotech::User->search(email => $email);
      die "Sorry, that email address was not found. Did you register with a different address?\n" unless $user;
      eval {
	$bibliotech->validate_user_can_login($user);  # if you can't login there's no point
      };
      if ($@) {
	(my $e = $@) =~ s/\n$//;  # unchomp
	my $siteemail = $bibliotech->siteemail;
	die "$e Because your account is inaccessible, we cannot help with your password at this time. If you require assistance please <a href=\"mailto:$siteemail\">email us</a>.\n";
      }

      my $username = $user->username;
      my $time     = Bibliotech::Util::time();
      my $code     = substr(md5_hex(join($HASHSPLIT, $username, $time, $FORGOTTEN_PASSWORD_SECRET)), 0, 16);
      my $url      = "${location}forgotpw?user=${username}&time=${time}&code=${code}";
      my $subject  = $bibliotech->sitename.' password';

      $bibliotech->notify_user($user,
			       file    => 'forgotpw_email',
			       subject => $subject,
			       var     => {url => $url, username => $username});
    };
    if ($@) {
      $validationmsg = $@;
    }
    else {
      my $o = $cgi->h1('Forgotten Password');
      $o .= $cgi->p('A message has been sent to the email address you gave us.');
      return Bibliotech::Page::HTML_Content->simple($o);
    }
  }
  elsif (my $username = $cgi->param('user')) {
    my $user;
    my $updated = 0;
    eval {
      $user    = Bibliotech::User->new($username) or die "User not found.\n";
      my $time = $cgi->param('time') or die "No time parameter.\n";
      my $code = $cgi->param('code') or die "No code parameter.\n";
      my $now  = Bibliotech::Util::time();
      $time =~ /^\d+$/            or die "Time parameter must be numeric.\n";
      $time <= $now + 60          or die "Time parameter is more recent than my clock!\n";  # allow small reset
      $time >= $now - 10*24*60*60 or die "Time parameter is over 10 days old; please complete the form again.\n";
      length $username <= 40      or die "Username too long!\n";  # guard against DOS via MD5 algorithm
      my $real = substr(md5_hex(join($HASHSPLIT, $username, $time, $FORGOTTEN_PASSWORD_SECRET)), 0, 16);
      $code eq $real              or die "Code parameter is incorrect.\n";
      if (my $password = $cgi->param('password')) {
	my $password2  = $cgi->param('password2');
	eval { Bibliotech::Component::RegisterForm->validate_password($password, $password2); };
	die "Step 2: $@" if $@;
	$user->password($password);
	$user->mark_updated;
	$updated = 1;
      }
    };
    if ($@) {
      $validationmsg = $@;
    }
    elsif ($updated) {
      # use the genuine login form action so we are sure to get it right
      my $redirect_uri = Bibliotech::Component::LoginForm->do_login_and_return_location($user, $bibliotech);
      undef $user;
      die "Location: $redirect_uri\n";
    }
    if (!$validationmsg or $validationmsg =~ /^Step 2: /) {
      $validationmsg =~ s/^Step 2: // if $validationmsg;

      my $o = $self->tt('compforgotpwstep2', undef, $self->validation_exception('', $validationmsg));

      my $javascript_first_empty = $self->firstempty($cgi, 'forgotpw', qw/password/);

      return Bibliotech::Page::HTML_Content->new({html_parts => {main => $o},
						   javascript_onload => ($main ? $javascript_first_empty : undef)});
    }
  }

  my $o = $self->tt('compforgotpw', undef, $self->validation_exception('', $validationmsg));

  my $javascript_first_empty = $self->firstempty($cgi, 'forgotpw', qw/email/);

  return Bibliotech::Page::HTML_Content->new({html_parts => {main => $o},
					       javascript_onload => ($main ? $javascript_first_empty : undef)});
}

1;
__END__
