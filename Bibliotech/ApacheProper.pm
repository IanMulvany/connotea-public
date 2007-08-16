# Copyright 2007 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::ApacheProper module just loads Apache2.

package Bibliotech::ApacheProper;
use base 'Exporter';

our @EXPORT = qw(OK NOT_FOUND AUTH_REQUIRED
		 SERVER_ERROR SERVICE_UNAVAILABLE
		 DECLINED FORBIDDEN REDIRECT
		 HTTP_OK HTTP_NOT_FOUND HTTP_UNAUTHORIZED
		 HTTP_INTERNAL_SERVER_ERROR HTTP_SERVICE_UNAVAILABLE
		 HTTP_DECLINED HTTP_FORBIDDEN HTTP_REDIRECT);

use Bibliotech::Config;

BEGIN {
  if (Bibliotech::Config->get('MOD_PERL_WORKAROUND')) {  # needed on RHEL 3
    require Apache2;
    require Apache::compat;
    require Apache::Const;
    Apache::Const->import(':common', ':http');
    require CGI;
  }
  else {  # RHEL 4 and elsewhere
    require Apache2::compat;
    require Apache2::Const;
    Apache2::Const->import(':common', ':http');
    require Apache::File;
    require CGI;
  }
}

1;
__END__
