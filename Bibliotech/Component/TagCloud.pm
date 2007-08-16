# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::TagCloud class provides a tag cloud.

package Bibliotech::Component::TagCloud;
use strict;
use base 'Bibliotech::Component';
use Bibliotech::DBI;
use Bibliotech::Config;
use List::Util qw/min max/;

our $TAG_CLOUD_WINDOW = Bibliotech::Config->get('TAG_CLOUD_WINDOW') || '60 DAY';
our $TAG_CLOUD_LAG    = Bibliotech::Config->get('TAG_CLOUD_LAG')    || '10 MINUTE';
our $TAG_CLOUD_IGNORE = Bibliotech::Config->get('TAG_CLOUD_IGNORE') || ['uploaded'];

sub last_updated_basis {
  ('DBI');
}

sub lazy_update {
  3600;
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $cached = $self->memcache_check(class => __PACKAGE__);
  return $cached if defined $cached;

  my $doc = $self->html_content_calc;

  return $self->memcache_save(Bibliotech::Page::HTML_Content->simple($doc));
}

sub tags {
  # 1 = act as visitor
  Bibliotech::Tag->search_for_tag_cloud_in_window($TAG_CLOUD_WINDOW, $TAG_CLOUD_LAG, $TAG_CLOUD_IGNORE, 1);
}

sub html_content_calc {
  my $self = shift;
  my @tags = tags();
  my $cgi  = $self->bibliotech->cgi;
  map { $_->memory_score_frequency(log      $_->memory_score_frequency)    } @tags;  # natural log correction
  map { $_->memory_score_recency  (log (abs($_->memory_score_recency)||1)) } @tags;  # natural log correction
  my $highest_frequency = max(map { abs($_->memory_score_frequency)    	   } @tags);
  my $highest_recency   = max(map { abs($_->memory_score_recency)      	   } @tags);
  return $cgi->div({id => 'tag-cloud'},
		   join ("\n",
			 map { $self->render_tag($_, $highest_frequency, $highest_recency) }
			 sort { lc($a->name) cmp lc($b->name) }
			 @tags
			 )
		   );
}

sub render_tag {
  my ($self, $tag, $highest_frequency, $highest_recency) = @_;
  my $relative_frequency = $highest_frequency ? abs($tag->memory_score_frequency) / $highest_frequency : 0;
  my $relative_recency   = $highest_recency   ? abs($tag->memory_score_recency)   / $highest_recency   : 0;
  my $frequency_bin 	 = int($relative_frequency / 0.1);
  my $recency_bin   	 = 10 - int($relative_recency / 0.1);
  my $class              = "tag_cloud tag_cloud_frequency_${frequency_bin} tag_cloud_recency_${recency_bin}";
  my $link               = $tag->link($self->bibliotech);
  $link =~ s/<a /<a class="$class" /;
  return $link;
}

# Example of CSS code that would then apply to the classes called in render_tag():
#
#   div.tag_cloud_container { border: 1px solid #97a9b7; padding: 15px; text-align: justify }
#   a.tag_cloud { font-weight: bold; text-decoration: none; line-height: 30px; margin: 0 3px 0 3px }
#   a.tag_cloud:hover { text-decoration: underline; color: black }
#   a.tag_cloud_frequency_0 { font-size: 8px }
#   a.tag_cloud_frequency_1 { font-size: 10px }
#   a.tag_cloud_frequency_2 { font-size: 13px }
#   a.tag_cloud_frequency_3 { font-size: 15px }
#   a.tag_cloud_frequency_4 { font-size: 17px }
#   a.tag_cloud_frequency_5 { font-size: 19px }
#   a.tag_cloud_frequency_6 { font-size: 22px }
#   a.tag_cloud_frequency_7 { font-size: 24px }
#   a.tag_cloud_frequency_8 { font-size: 26px }
#   a.tag_cloud_frequency_9 { font-size: 28px }
#   a.tag_cloud_frequency_10 { font-size: 30px }
#   a.tag_cloud_recency_0 { color: #97A9B7 }
#   a.tag_cloud_recency_1 { color: #9C99AA }
#   a.tag_cloud_recency_2 { color: #A1889D }
#   a.tag_cloud_recency_3 { color: #A67790 }
#   a.tag_cloud_recency_4 { color: #AC6683 }
#   a.tag_cloud_recency_5 { color: #B15575 }
#   a.tag_cloud_recency_6 { color: #B64468 }
#   a.tag_cloud_recency_7 { color: #BC335B }
#   a.tag_cloud_recency_8 { color: #C1224E }
#   a.tag_cloud_recency_9 { color: #C61141 }
#   a.tag_cloud_recency_10 { color: #CC0033 }

1;
__END__
