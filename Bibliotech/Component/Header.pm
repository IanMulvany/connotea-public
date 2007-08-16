# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::Header class provides a header.

package Bibliotech::Component::Header;
use strict;
use base 'Bibliotech::Component';

sub last_updated_basis {
  'LOGIN';
}

sub html_content {
  my ($self, $class, $verbose) = @_;
  my $bibliotech = $self->bibliotech;
  my $popup      = $bibliotech->command->is_popup;
  my $location   = $bibliotech->location;
  my $cgi        = $bibliotech->cgi;
  my $username   = $bibliotech->request->notes->{'username'};

  my $o = $cgi->div({id => 'logininfo'},
		    $username
		    ? ('logged in as', $cgi->strong($username), '&nbsp;',
		       ($self->options->{library}
			? ($cgi->a({href   => $location.'library',
				    class  => 'mylibrary-home',
				    $popup ? (target => '_blank') : (),
				    },
				   'My Library'),
			   '&nbsp;')
			: ()
			),
		       $cgi->a({href => $location.'logout'},
			       $cgi->img({src => $location.'logout.gif', alt => 'logout', border => 0, id => 'loginoutbutton'}))
		       )
		    : ('&nbsp;',
		       $cgi->a({href => $location.'login'},
			       $cgi->img({src => $location.'login.gif', alt => 'login', border => 0, id => 'loginoutbutton'})))
		    );

  $o .= $cgi->a({href => $location, class => 'logolink'},
			  $cgi->img({src => $location.'connotealogo.gif', alt => 'Connotea', border => 0, id => 'connotealogo'}));

  return Bibliotech::Page::HTML_Content->simple($o);
}

1;
__END__
