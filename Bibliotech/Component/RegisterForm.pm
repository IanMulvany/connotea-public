# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::RegisterForm class provides a registration form.

package Bibliotech::Component::RegisterForm;
use strict;
use base 'Bibliotech::Component';
use Bibliotech::DBI;
use Bibliotech::Component::VerifyForm;

sub last_updated_basis {
  ('NOW');  # not an oft-used page, just always load exactly correct registration details
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $bibliotech = $self->bibliotech;
  my $cgi        = $bibliotech->cgi;
  my $user       = $bibliotech->user;
  my $user_id    = defined $user ? $user->user_id : undef;

  $bibliotech->last_modified_no_cache;  # tell AOL etc to always reload

  # parameter cleaning - need this to keep utf-8 output from messing up on a reload
  foreach (qw/username password password2 firstname lastname email/) {
    my $value = $self->cleanparam($cgi->param($_));
    $cgi->param($_ => $value) if $value;
  }

  my $validation;
  my $button = $cgi->param('button');
  if ($button =~ /^(?:Register|Update)$/i) {
    my $o;
    eval {
      die $self->validation_exception('', "You cannot update if you are not logged in.\n")
	  if $button =~ /^Update$/i and !defined($user);
      my $username  = $cgi->param('username');
      my $password  = $cgi->param('password');
      my $password2 = $cgi->param('password2');
      my $firstname = $cgi->param('firstname');
      my $lastname  = $cgi->param('lastname');
      my $email     = $cgi->param('email');
      my $email2    = $cgi->param('email2');
      $self->validate_firstname($firstname);
      $self->validate_lastname($lastname);
      $self->validate_username($username) if $button =~ /^Register$/i or $username;
      $self->validate_password($password, $password2);
      $self->validate_email($email, $email2);
      eval {
	if ($button =~ /^Register$/i) {
	  my $new_user = $bibliotech->new_user($username, $password, $firstname, $lastname, $email);
	  if ($new_user->active) {
	    # we are active because a setting has caused verification to be skipped
	    my $url = Bibliotech::Component::VerifyForm->do_virgin_login_and_return_location($new_user, $bibliotech);
	    die "Location: $url\n";
	  }
	  $o = $self->tt('compregisterthanks');
	}
	else {
	  $bibliotech->update_user($user_id, $password, $firstname, $lastname, $email, $username);
	  $o = $self->tt('compupdatethanks');
	}
      };
      if ($@) {
	foreach (qw/username password email/) {
	  die $self->validation_exception($_ => $@) if $@ =~ /$_/;
	}
	die $@;
      }
    };
    if ($@) {
      die $@ if $@ =~ /at .* line \d+/ or $@ =~ /^Location:/;  # need Location for new_user->active check
      $validation = $@;
    }
    else {
      return Bibliotech::Page::HTML_Content->simple($o);
    }
  }

  if ($user and !$validation) {
    my %user = $bibliotech->load_user($user->user_id);
    $cgi->param($_ => $user{$_}) foreach (keys %user);
    $cgi->param(password2 => $user{password});
    $cgi->param(email2 => $user{email});
  }

  my $o = $self->tt('compregister',
		    {from_openid => do { local $_ = $cgi->param('from'); $_ ? $_ eq 'openid' : 0; }},
		    $validation);

  my $javascript_first_empty = $self->firstempty($cgi, 'register', [qw/firstname lastname username password password2 email email2/], $validation);

  return Bibliotech::Page::HTML_Content->new({html_parts => {main => $o},
					      javascript_onload => ($main ? $javascript_first_empty : undef)});
}

sub validate_firstname {
  my ($self, $firstname) = @_;
  $self->validate_tests('firstname', sub { Bibliotech::User::_validate_firstname($firstname); });
}

sub validate_lastname {
  my ($self, $lastname) = @_;
  $self->validate_tests('lastname', sub { Bibliotech::User::_validate_lastname($lastname); });
}

sub validate_username {
  my ($self, $username) = @_;
  $self->validate_tests('username', sub { Bibliotech::User::_validate_username($username); });
}

sub validate_password {
  my ($self, $password, $password2) = @_;
  $self->validate_tests('password', sub {
    Bibliotech::User::_validate_password($password);
    $password2               or die [password2 => "Please re-enter your password for verification.\n"];
    $password eq $password2  or die [password2 => "The passwords do not match.\n"];
  });
}

sub validate_email {
  my ($self, $email, $email2) = @_;
  $self->validate_tests('email', sub {
    Bibliotech::User::_validate_email($email);
    $email2                  or die [email2 => "Please re-enter your email address for verification.\n"];
    $email eq $email2        or die [email2 => "The email addresses do not match.\n"];
  });
}

1;
__END__
