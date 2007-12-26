# Copyright 2006 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::KillSpammerForm class provides an
# interface to submit usernames of spammers for torture, er, removal.

package Bibliotech::Component::KillSpammerForm;
use strict;
use base 'Bibliotech::Component';

our $KILLSPAMMERFORM_ADMIN_USERS = __PACKAGE__->cfg('ADMIN_USERS');
$KILLSPAMMERFORM_ADMIN_USERS = [$KILLSPAMMERFORM_ADMIN_USERS] unless ref $KILLSPAMMERFORM_ADMIN_USERS;

sub last_updated_basis {
  'NOW';
}

sub deactivate_username {
  my $self     = shift or die 'no self object';
  my $username = shift or die 'no username';
  my $reason   = shift or die 'no reason code';
  my $user     = Bibliotech::User->new($username) or die "Cannot find $username.\n";
  die "$username already deactivated.\n" unless $user->active;
  $user->deactivate($self->bibliotech, $reason, 0);
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $user       = $self->getlogin or return $self->saylogin('to deactive spammer accounts');
  my $username   = $user->username;
  grep { $username eq $_ } @{$KILLSPAMMERFORM_ADMIN_USERS} or return Bibliotech::Page::HTML_Content->simple('Not an admin.');
  my $bibliotech = $self->bibliotech;
  my $cgi        = $bibliotech->cgi;
  my $validationmsg;
  my @report;

  if (my $usernames = $self->cleanparam($cgi->param('user')) and $cgi->request_method eq 'POST') {
    my $reason = $self->cleanparam($cgi->param('reason')) || 'resignation';
    eval {
      my @again;  # list failed usernames to put back in form field
      my @users = split(/[,\s]\s*/, $usernames) or die "No usernames provided.\n";
      foreach my $username (@users) {
	eval {
	  $self->deactivate_username($username, $reason);
	};
	if ($@) {
	  die $@ if $@ =~ / at .* line /;
	  push @report, $@;
	  push @again, $username;
	}
	else {
	  push @report, "\'$username\' processed with \'$reason\' action.";
	}
      }
      @again ? $cgi->param(user => join(' ', @again)) : $cgi->Delete('user');
    };
    $validationmsg = $@ if $@;
  }

  my $o = '';

  $o .= $cgi->div({class => 'errormsg'}, $validationmsg) if $validationmsg;
  $o .= $cgi->div({class => 'actionmsg'}, map { $_.$cgi->br } @report) if @report;

  $o .= $cgi->div($cgi->h1('Deactivate Users and Related Actions'),
		  $cgi->start_form(-method => 'POST', -action => $bibliotech->location.'killspammer'),
		  $cgi->textarea(-id => 'userbox', -class => 'searchtextctl', -name => 'user', -cols => 60, -rows => 10),
		  $cgi->br,
		  $cgi->popup_menu(-name    => 'reason',
				   -id      => 'reasonselect',
				   -values  => [qw/resignation spammer undo-spammer no-quarantine/],
				   -labels  => {'resignation'   => 'Resignation',
						'spammer'       => 'Spammer',
						'undo-spammer'  => 'Undo Spammer',
						'no-quarantine' => 'Unquarantine Posts',
				               },
				   -default => 'spammer'),
		  $cgi->br,
		  $cgi->submit(-id => 'submitbutton', -class => 'buttonctl', -name => 'button', -value => 'Submit'),
		  $cgi->end_form,
		  );

  $self->discover_main_title($o);

  return Bibliotech::Page::HTML_Content->simple($o);
}

1;
__END__
