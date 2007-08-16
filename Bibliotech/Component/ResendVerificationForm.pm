# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::VerifyForm class provides output to show when a
# new user is verified (gets their email and clicks the link).

package Bibliotech::Component::ResendVerificationForm;
use strict;
use base 'Bibliotech::Component';

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

      # use this test in reverse - we want it to die
      eval { $bibliotech->validate_user_can_login($user) };
      unless ($@) {
	my $siteemail = $bibliotech->siteemail;
	die "Your user is already verified for login. Try <a href=\"${location}login\">login</a> or a <a href=\"${location}forgotpw\">forgotten password request</a>. If you require assistance please <a href=\"mailto:$siteemail\">email us</a>.\n";
      }

      $bibliotech->new_user_send_email($user);
    };
    if ($@) {
      $validationmsg = $@;
    }
    else {
      return Bibliotech::Page::HTML_Content->simple($self->tt('compresendregthanks'));
    }
  }

  my $o = $self->tt('compresendreg', undef, $self->validation_exception('', $validationmsg));

  my $javascript_first_empty = $self->firstempty($cgi, 'resendreg', qw/email/);

  return Bibliotech::Page::HTML_Content->new({html_parts => {main => $o},
					       javascript_onload => ($main ? $javascript_first_empty : undef)});
}

1;
__END__
