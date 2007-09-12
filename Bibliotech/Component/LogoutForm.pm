# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::LogoutForm class provides a logout form.

package Bibliotech::Component::LogoutForm;
use strict;
use base 'Bibliotech::Component';
use Bibliotech::Component::LoginForm;
use Bibliotech::Cookie;

sub last_updated_basis {
  ('LOGIN');
}

# analogous to LoginForm set_cookie()
sub set_cookie {
  my ($self, $bibliotech) = @_;
  my $add = Bibliotech::Component::LoginForm::_cookie_setter($bibliotech->request);
  $add->(Bibliotech::Cookie->logout_cookie($bibliotech));
}

sub do_logout_and_return_location {
  my ($self, $bibliotech) = @_;
  $self->set_cookie($bibliotech);
  return $bibliotech->location;
}

sub html_content {
  my ($self, $class, $verbose) = @_;
  die 'Location: '.$self->do_logout_and_return_location($self->bibliotech)."\n";
}

1;
__END__
