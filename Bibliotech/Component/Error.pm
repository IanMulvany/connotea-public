# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::Error class provides error output structure.

package Bibliotech::Component::Error;
use strict;
use base 'Bibliotech::Component';

sub last_updated_basis {
  'NOW';
}

sub html_content {
  my ($self, $class, $verbose) = @_;
  return Bibliotech::Page::HTML_Content->simple($self->bibliotech->cgi->div({class => 'errormsg'}, $self->bibliotech->error));
}

1;
__END__
