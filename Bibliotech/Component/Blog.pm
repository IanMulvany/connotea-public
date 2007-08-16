# Copyright 2007 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::Blog class provides a blog page created
# from an external RSS feed with links thereto.

package Bibliotech::Component::Blog;
use strict;
use base 'Bibliotech::Component';
use XML::Feed;

our $FEED_URL = URI->new(__PACKAGE__->cfg('FEED_URL') || 'file:///tmp/blog.xml');

sub last_updated_basis {
  'NOW';
}

sub lazy_update {
  900;
}

sub get_feed {
  my $feed = XML::Feed->parse($FEED_URL) or return;
  bless $feed, 'Bibliotech::Component::Blog::Feed::RSS';
  return $feed;
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;
  my $cached = $self->memcache_check(class  => __PACKAGE__,
				     method => 'html_content');
  return $cached if defined $cached;
  my $o = $self->html_content_calc($class, $verbose, $main);
  return $self->memcache_save($o);
}

sub html_content_calc {
  my ($self, $class, $verbose, $main) = @_;
  my $o = do { my $feed = $self->get_feed;
	       $feed ? $self->tt('compblog', {url => $FEED_URL, feed => $feed})
                     : 'News feed unavailable at this time.'; };
  return Bibliotech::Page::HTML_Content->simple($o);
}

package Bibliotech::Component::Blog::Feed::RSS;
use base 'XML::Feed::RSS';

sub entries {
  [map { bless $_, 'Bibliotech::Component::Blog::Feed::Entry::RSS' } shift->SUPER::entries];
}

package Bibliotech::Component::Blog::Feed::Entry::RSS;
use base 'XML::Feed::Entry::RSS';
use Bibliotech::DBI;

sub issued {
  bless shift->SUPER::issued, 'Bibliotech::Date';
}

1;
__END__
