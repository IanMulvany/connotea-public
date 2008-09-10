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
  my $validationmsg;

  if ($cgi->request_method eq 'POST') {
    my $button = lc($cgi->param('button'));
    if ($button eq 'cancel') {
      die "Location: ".$bibliotech->location."library\n";
    }
    elsif ($button eq 'resign') {
      eval {
	die "You must confirm your choice by selecting Yes.\n" if $cgi->param('confirm') ne 'yes';
	if (my $comment = $self->cleanparam($cgi->param('comment'))) {
	  $bibliotech->notify_admin(body => 'User '.$user->username." leaves this comment upon resignation:\n\n$comment\n");
	}
	$bibliotech->user->deactivate($bibliotech, 'resignation');
      };
      if ($@) {
	$validationmsg = $@;
      }
      else {
	die 'Location: '.Bibliotech::Component::LogoutForm->do_logout_and_return_location($bibliotech)."\n";
      }
    }
  }

  my $o = '';

  $o .= $cgi->div({class => 'errormsg'}, $validationmsg) if $validationmsg;

  $o .= $cgi->div($cgi->h1('Resign Account'),
		  $cgi->start_form(-method => 'POST', -action => $bibliotech->location.'resign'),
		  $cgi->p('This action will resign the '.$bibliotech->sitename.' user '.$cgi->b($user->username).'.'),
		  $cgi->p('Are you sure that you want to delete your account?'),
		  $cgi->popup_menu(-name    => 'confirm',
				   -id      => 'confirmselect',
				   -values  => [qw/no yes/],
				   -labels  => {'no'  => 'No',
						'yes' => 'Yes',
				               },
				   -default => 'no'),
		  $cgi->p('If you would like to leave a comment for our team as you resign, you may optionally do so here:'),
		  $cgi->textarea(-id => 'commentbox', -class => 'searchtextctl', -name => 'comment', -cols => 60, -rows => 5),
		  $cgi->br,
		  $cgi->submit(-id => 'submitbutton', -class => 'buttonctl', -name => 'button', -value => 'Resign'),
		  $cgi->submit(-id => 'cancelbutton', -class => 'buttonctl', -name => 'button', -value => 'Cancel'),
		  $cgi->end_form,
		  );

  $self->discover_main_title($o);

  return Bibliotech::Page::HTML_Content->simple($o);
}

1;
__END__
