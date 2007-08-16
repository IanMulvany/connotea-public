# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::AddGroupForm class provides a group add form.

package Bibliotech::Component::AddGroupForm;
use strict;
use base 'Bibliotech::Component';

sub last_updated_basis {
  ('DBI', 'LOGIN')
}

sub html_content {
  my ($self, $class, $verbose, $main, $action) = @_;

  my $bibliotech = $self->bibliotech;
  my $cgi        = $bibliotech->cgi;
  my $location   = $bibliotech->location;

  my ($add, $edit) = (0, 0);
  if (!$action or $action eq 'add') {
    $action = 'add';
    $add = 1;
  }
  elsif ($action eq 'edit') {
    $edit = 1;
  }

  my $user = $self->getlogin;
  unless ($user) {
    my $msg;
    if ($action eq 'add') {
      $msg = 'to add a group';
    }
    elsif ($action eq 'edit') {
      $msg = 'to edit a group';
    }
    return $self->saylogin($msg);
  }

  my $username = $user->username;

  # parameter cleaning
  foreach (qw/name description members/) {
    my $value = $self->cleanparam($cgi->param($_));
    $cgi->param($_ => $value) if $value;
  }

  my $validationmsg;
  my $button = $cgi->param('button');
  if ($button =~ /^Add/ or $button =~ /^Save/) {
    my $name = $cgi->param('name');
    my $gang;
    eval {
      my $func = $action.'group';
      $gang = $bibliotech->$func(user => $user,
				 (map {$_ => $cgi->param($_) || undef} qw/name description private/),
				 members => [grep { $_ && /\S/ } split(/\W+/, $cgi->param('members'))]);
    };
    if ($@) {
      $validationmsg = $@;
    }
    else {
      die "Location: $location".(defined($gang) && $name ? "group/$name" : 'library')."\n";
    }
  }
  elsif ($button =~ /^Cancel/) {
    die "Location: ${location}library\n";
  }
  elsif ($button =~ /^Remove/) {
    eval {
      $bibliotech->editgroup(user => $user, name => $cgi->param('name') || undef, members => []);
    };
    if ($@) {
      $validationmsg = $@;
    }
    else {
      die "Location: ${location}library\n";
    }
  }

  my ($name, $gang);
  eval {
    if ($add) {
      $cgi->param(members => $username) unless $cgi->param('members');
    }
    else {
      if ($name = $cgi->param('name')) {
	if ($gang = Bibliotech::Gang->new($name)) {
	  die "You are not the owner of this group.\n" unless $gang->owner->user_id == $user->user_id;
	  foreach (qw/description private/) {
	    $cgi->param($_ => $gang->$_);
	  }
	  $cgi->param(members => join(', ', sort map($_->username, $gang->users)));
	}
      }
      die "No group.\n" unless $gang;
    }
  };
  return Bibliotech::Page::HTML_Content->simple($cgi->div({class => 'errormsg'}, $@)) if $@;

  my $o = $self->tt('compaddgroup',
		    {action  => $action,
		     is_add  => $action eq 'add',
		     is_edit => $action eq 'edit',
		    },
		    $self->validation_exception('', $validationmsg));

  my $javascript_first_empty = $self->firstempty($cgi, $action, qw/name members/);

  return Bibliotech::Page::HTML_Content->new({html_parts => {main => $o},
					       javascript_onload => ($main ? $javascript_first_empty : undef)});
}

1;
__END__
