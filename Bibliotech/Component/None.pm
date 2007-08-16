# Copyright 2006 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::None class provides no content; it is
# useful only when the outer calling context provides all of the
# content; for example, if the components are going into TT output but
# the TT template already has all the content you need.

package Bibliotech::Component::None;
use strict;
use base 'Bibliotech::Component';

sub last_updated_basis {
  ();
}

sub html_content {
  Bibliotech::Page::HTML_Content->blank;
}

1;
__END__
