# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::AddUserTagAnnotationForm class
# provides an annotation add form.

package Bibliotech::Component::AddUserTagAnnotationForm;
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
      $msg = 'to add a note';
    }
    elsif ($action eq 'edit') {
      $msg = 'to edit a note';
    }
    return $self->saylogin($msg);
  }

  my $username = $user->username;

  # parameter cleaning
  foreach (qw/tag entry/) {
    my $value = $self->cleanparam($cgi->param($_));
    $cgi->param($_ => $value) if $value;
  }

  my $validationmsg;
  my $overwrite = 0;

  my ($tagname, $tag, $entry, $user_tag_annotation);
  my $button = $cgi->param('button');
  my $performed = 0;
  eval {
    if ($button =~ /^Cancel/) {
      die "Location: ${location}library\n";
    }
    if ($tagname = $cgi->param('tag')) {
      $tag = $bibliotech->parser->want_single_tag_but_may_have_more($tagname) or die "Unrecognized tag name.\n";
      $tagname = $tag->name;
    }
    if ($entry = $cgi->param('entry')) {
      die "Please enter a tag that you would like this note to be associated with.\n" unless $tagname;
    }
    if ($button =~ /^Add/ or $button =~ /^Save/) {
      my $func = $action.'uta';
      $bibliotech->$func(user => $user, tag => $tag, entry => $entry);
      $performed = 1;
    }
    elsif ($button =~ /^Remove/) {
      $bibliotech->edituta(user => $user, tag => $tag, entry => undef);
      $performed = 1;
    }
  };
  if ($@) {
    die $@ if $@ =~ /^Location: /;
    $validationmsg = $@;
    if ($validationmsg =~ /already have a note/) {
      $overwrite = $validationmsg =~ /confirm/ ? 1 : 2;
      $action = 'edit';
      $add = 0;
      $edit = 1;
    }
  }
  else {
    die "Location: ${location}user/".$user->username.'/tag/'.$tagname."\n" if $performed;
  }

  eval {
    if ($edit) {
      if ($tag) {
	($user_tag_annotation) = Bibliotech::User_Tag_Annotation->search(user => $user, tag => $tag);
	die "No note.\n" unless defined $user_tag_annotation;
	$entry ||= $user_tag_annotation->comment->entry;
	$entry =~ s| *<br ?/?>|\n|g;
	$cgi->param(entry => $entry);
      }
      else {
	die "No tag.\n";
      }
    }
  };
  return Bibliotech::Page::HTML_Content->simple($cgi->div({class => 'errormsg'}, $@)) if $@;

  my $o = $self->tt('compaddtagnote',
		    {action  => $action,
		     is_add  => $action eq 'add',
		     is_edit => $action eq 'edit',
		     overwrite => $overwrite,
		     overwrite_output => sub { $user_tag_annotation->html_content($bibliotech, 'existing', 1, 0); },
		    },
		    $self->validation_exception('', $validationmsg));

  my $javascript_first_empty = $self->firstempty($cgi, $action, qw/tag entry/);

  return Bibliotech::Page::HTML_Content->new({html_parts => {main => $o},
					       javascript_onload => ($main ? $javascript_first_empty : undef)});
}

1;
__END__
