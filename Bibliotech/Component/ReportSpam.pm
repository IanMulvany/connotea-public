# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::Spam provides mechanism for marking a bookmark
# as Spam.

package Bibliotech::Component::ReportSpam;
use strict;
use base 'Bibliotech::Component';

use Bibliotech::DBI;

sub list {
  shift->bibliotech->query->user_bookmarks(num => 1000);
}

sub mark {
  my ($self, $reporting_user, $spam_user_bookmark_iter) = @_;
  my $count = 0;
  while (my $user_bookmark = $spam_user_bookmark_iter->next) {
    next if $user_bookmark->id == $reporting_user->id;
    $user_bookmark->link_spam($reporting_user);
    $count++;
  }
  return $count;
}

sub mark_list {
  my ($self, $reporting_user) = @_;
  $self->mark($reporting_user, scalar $self->list);
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $bibliotech = $self->bibliotech;
  my $user       = $bibliotech->user;

  unless ($user) {
    return $self->saylogin('to report this as spam');
  }

  unless ($user->active) {
    return Bibliotech::Page::HTML_Content->simple('Your account is inactive.');
  }

  unless ($bibliotech->command->filters_used) {
    return Bibliotech::Page::HTML_Content->simple('Please click "report spam" on individual posts.');
  }

  #unless (join(',', sort $bibliotech->command->filters_used) eq 'bookmark,user') {
    #return Bibliotech::Page::HTML_Content->simple('Please click "report spam" on individual posts.');
  #}

  my $count = $self->mark_list($user);

  return Bibliotech::Page::HTML_Content->simple('Thank you. The post'.($count > 1 ? 's' : '').' you have marked will be reviewed, along with all other posts by the spamming user.');
}

1;
__END__
