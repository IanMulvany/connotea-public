# Copyright 2006 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CGI class overrides some things from CGI.

package Bibliotech::CGI;
use strict;
use base 'CGI';

sub super_start_form {
  shift->SUPER::start_form(@_);
}

sub start_form {
  my $form = shift->SUPER::start_form(@_);

  # hack to change enctype to old urlencoded system
  # CGI.pm insists on using multipart for XHTML output but this causes cgi_error() to return an error
  # '400 Bad request (malformed multipart POST)' when checked during init for some people
  # an alternative approach would be to avoid doing that check (we do it voluntarily)
  # (this has to be a substitution because start_form() won't accept an enctype in XHTML mode)
  $form =~ s|multipart/form-data|application/x-www-form-urlencoded|g;

  return $form;
}

1;
__END__
