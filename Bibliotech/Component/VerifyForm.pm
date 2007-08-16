# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::VerifyForm class provides output to show when a
# new user is verified (gets their email and clicks the link).

package Bibliotech::Component::VerifyForm;
use strict;
use base 'Bibliotech::Component';
use Bibliotech::Component::LoginForm;

sub last_updated_basis {
  'NOW';
}

sub do_virgin_login_and_return_location {
  my ($self, $user, $bibliotech) = @_;
  Bibliotech::Component::LoginForm->set_cookie($user, $bibliotech, 1);
  return $bibliotech->location.'getting_started';
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $bibliotech = $self->bibliotech;
  my $cgi        = $bibliotech->cgi;
  my $user_id    = $cgi->param('userid');
  my $verifycode = $cgi->param('code');

  my $user = eval {
    $user_id && $verifycode or die "Verification parameters not supplied.\n";
    $bibliotech->verify_user($user_id, $verifycode);
    return $bibliotech->allow_first_login($user_id);
  };
  if ($@) {
    die $@ if $@ =~ / at .* line /;
    return Bibliotech::Page::HTML_Content->simple($cgi->div({class => 'errormsg'}, $@));
  }

  die 'Location: '.$self->do_virgin_login_and_return_location($user, $bibliotech)."\n";
}

1;
__END__
