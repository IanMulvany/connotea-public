# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::Toolbox class provides a toolbox.

package Bibliotech::Component::Toolbox;
use strict;
use base 'Bibliotech::Component';

sub last_updated_basis {
  ('DBI', 'LOGIN', shift->include_basis('/toolbox'));
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;
  return Bibliotech::Page::HTML_Content->simple($self->include('/toolbox', $class, $verbose, $main));
}

1;
__END__
