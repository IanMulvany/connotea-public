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
use Bibliotech::AuthCookie;

sub last_updated_basis {
  ('LOGIN');
}

sub html_content {
  my ($self, $class, $verbose) = @_;
  my $cookie = Bibliotech::AuthCookie->logout_cookie($self->bibliotech);
  $self->bibliotech->request->err_headers_out->add('Set-Cookie' => $cookie);
  die 'Location: '.$self->bibliotech->location."\n";
}

1;
__END__
