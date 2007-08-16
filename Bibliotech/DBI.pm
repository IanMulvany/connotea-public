# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This file provides all database-level methods, with one class
# representing each table, plus some extra classes.
#
# *** IMPORTANT: ***
# All of this code is heavily based on Class::DBI and Ima::DBI so a
# familiarity with the documentation and source code for those modules
# is a good idea.

use strict;

require Bibliotech::DBI::Base;
require Bibliotech::DBI::Unwritten;
require Bibliotech::DBI::User;
require Bibliotech::DBI::Gang;
require Bibliotech::DBI::User_Gang;
require Bibliotech::DBI::Bookmark;
require Bibliotech::DBI::Unwritten::Bookmark;
require Bibliotech::DBI::Tag;
require Bibliotech::DBI::SpecialTagSet;
require Bibliotech::DBI::Annotation;
require Bibliotech::DBI::User_Tag_Annotation;
require Bibliotech::DBI::User_Bookmark;
require Bibliotech::DBI::Unwritten::User_Bookmark;
require Bibliotech::DBI::User_Bookmark_Tag;
require Bibliotech::DBI::User_Bookmark_Details;
require Bibliotech::DBI::User_Bookmark_Comment;
require Bibliotech::DBI::Comment;
require Bibliotech::DBI::Unwritten::Comment;
require Bibliotech::DBI::Bookmark_Details;
require Bibliotech::DBI::Citation;
require Bibliotech::DBI::Unwritten::Citation;
require Bibliotech::DBI::Citation::Identifier;
require Bibliotech::DBI::Author;
require Bibliotech::DBI::Unwritten::Author;
require Bibliotech::DBI::Citation_Author;
require Bibliotech::DBI::Journal;
require Bibliotech::DBI::Unwritten::Journal;
require Bibliotech::DBI::Date;

package URI::OpenURL;
# this routine from Tim Brody. Will be in next (0.4.2) release of URI::OpenURL
# (some changes made)

sub as_hybrid
{
  my $self = shift;
  my @KEVS = $self->query_form;
  # Add the referent
  my @md = $self->referent->metadata();
  # 'title' has been changed to 'jtitle'
  for(my $i = 0; $i < @md; $i+=2) {
    $md[$i] = 'title' if($md[$i] eq 'jtitle');
  }
  push @KEVS, @md;
  # Add the referrer's id
  if (my @id = $self->referrer->id) {
    push @KEVS, map { s/^info:(?:sid\/)?//; sid => $_; } @id;
  }
  # Add the referent's id
  if (my @id = $self->referent->id) {
    push @KEVS, map { s|^info:(\w+)/|$1:|; s/info://; s/sid://; /^(doi|pmid|bibcode|oai):/ ? (id => $_) : (); } @id;
  }
  # Return a new URI (otherwise we pollute ourselves)
  my $hybrid = new URI::OpenURL($self);
  $hybrid->query_form(@KEVS);
  $hybrid;
}

package Bibliotech::DBI::Class::DBI::Search::CaseInsensitive;
use base 'Class::DBI::Search::Basic';

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(@_);
  $self->type('= BINARY');
  return $self;
}

1;
__END__
