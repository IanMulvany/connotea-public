# Copyright 2006 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::ResignForm class provides an interface to
# let a user resign, that is, remove their own user.

package Bibliotech::Component::ResignForm;
use strict;
use base 'Bibliotech::Component';
use Bibliotech::Component::LogoutForm;

sub last_updated_basis {
  'NOW';
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $user       = $self->getlogin or return $self->saylogin('to resign');
  my $bibliotech = $self->bibliotech;
  my $cgi        = $bibliotech->cgi;
  my $validation;

  if ($cgi->request_method eq 'POST') {
    my $button = $cgi->param('button');
    if ($button) {
      my $confirm = $cgi->param('confirm');
      if (lc($button) eq 'cancel') {
	die "Location: ".$bibliotech->location."library\n";
      }
      elsif (lc($button) eq 'resign') {
	eval {
	  die $self->validation_exception(confirm => "Resignation will not be accepted unless you confirm with Yes.\n")
	      unless $confirm and lc($confirm) eq 'yes';
	  if (my $comment = $self->cleanparam($cgi->param('comment'))) {
	    $bibliotech->notify_admin(body => 'User '.$user->username." leaves this comment upon resignation:\n\n$comment\n");
	  }
	  $user->deactivate($bibliotech, 'resignation');
	};
	if ($@) {
	  die $@ if $@ =~ /at .* line \d+/;
	  $validation = $self->validation_exception(undef => $@);
	}
	else {
	  die 'Location: '.Bibliotech::Component::LogoutForm->do_logout_and_return_location($bibliotech)."\n";
	}
      }
    }
  }

  return Bibliotech::Page::HTML_Content->simple($self->tt('compresign', undef, $validation));
}

1;
__END__
