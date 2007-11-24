# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::PopularTags class provides a tag list.

package Bibliotech::Component::PopularTags;
use strict;
use base 'Bibliotech::Component::List';
use Bibliotech::DBI::Set;

our $POPULAR_TAGS_WINDOW       = Bibliotech::Config->get('POPULAR_TAGS_WINDOW')       || '7 DAY';
our $POPULAR_TAGS_LAG          = Bibliotech::Config->get('POPULAR_TAGS_LAG')          || '10 MINUTE';
our $POPULAR_TAGS_IGNORE       = Bibliotech::Config->get('POPULAR_TAGS_IGNORE')       || ['uploaded'];
our $POPULAR_TAGS_POST_MIN     = Bibliotech::Config->get('POPULAR_TAGS_POST_MIN')     || 5;
our $POPULAR_TAGS_USER_MIN     = Bibliotech::Config->get('POPULAR_TAGS_USER_MIN')     || 5;
our $POPULAR_TAGS_BOOKMARK_MIN = Bibliotech::Config->get('POPULAR_TAGS_BOOKMARK_MIN') || 5;

sub last_updated_basis {
  ('DBI');
}

sub lazy_update {
  10800;
}

sub list {
  my $num  = shift->bibliotech->command->num;
  my @set  = Bibliotech::Tag->search_for_popular_tags_in_window($POPULAR_TAGS_WINDOW,
								$POPULAR_TAGS_LAG,
								$POPULAR_TAGS_IGNORE,
								$POPULAR_TAGS_POST_MIN,
								$POPULAR_TAGS_USER_MIN,
								$POPULAR_TAGS_BOOKMARK_MIN,
								1,  # 1 = act as visitor
								$num);
  return wantarray ? @set : Bibliotech::DBI::Set->new(@set);
}

sub rss_content {
  my ($self, $verbose) = @_;
  my $bibliotech = $self->bibliotech;
  return map { 
    my $rss_hashref = $_->rss_content($bibliotech, $verbose);
    my $connotea_ns = ($rss_hashref->{connotea} ||= {});
    $connotea_ns->{postCount}     = $_->filtered_count;
    $connotea_ns->{userCount}     = $_->filtered_user_count;
    $connotea_ns->{bookmarkCount} = $_->filtered_article_count;
    $rss_hashref;
  } $self->list(main => 1);
}

sub main_heading {
  'Popular Tags';
}

sub main_description {
  my $sitename = shift->bibliotech->sitename;
  (my $period = lc $POPULAR_TAGS_WINDOW) =~ s/([^s])$/${1}s/;
  return "The most popular tags on $sitename in the last $period";
}

1;
__END__
