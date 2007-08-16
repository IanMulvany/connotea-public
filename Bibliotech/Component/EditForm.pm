# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::EditForm class provides a form to edit a
# bookmark, but this functionality is all written into AddForm, so we just
# base this module on that and call back to it.

package Bibliotech::Component::EditForm;
use strict;
use base 'Bibliotech::Component::AddForm';

sub html_content {
  my ($self, $class, $verbose, $main) = @_;
  return $self->SUPER::html_content($class, $verbose, $main, 'edit');
}

1;
__END__
