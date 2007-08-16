# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Import::FirefoxBookmarks class imports Firefox
# bookmarks

package Bibliotech::Import::FirefoxBookmarks;
use strict;
use base 'Bibliotech::Import';
use Netscape::Bookmarks;

sub name {
  'Firefox Bookmarks';
}

sub noun {
  'Firefox Bookmarks';
}

sub version {
  1.0;
}

sub api_version {
  1;
}

sub mime_types {
  ('text/html');
}

sub extensions {
  ('html');
}

sub understands {
  $_[1] =~ /<!DOCTYPE NETSCAPE-Bookmark-file\b/ ? 1 : 0;
}

sub parse {
  my $self = shift;
  my $doc = $self->doc or die 'no document';
  my $nb = Netscape::Bookmarks::parse_string(\$doc) or die 'no Netscape::Bookmarks object';
  my @links = $self->parse_category([], $nb);
  $self->data(new Bibliotech::Import::EntryList (map(new Bibliotech::Import::FirefoxBookmarks::Entry ($_), @links)));
  return 1;
}

sub parse_category {
  my $self = shift;
  my $category_path_titles_ref = shift or die 'must provide previous category path titles';
  my $category = shift or die 'must provide a category';
  $category->can('elements') or die 'not a Netscape::Bookmarks::Category object';
  my $elements = $category->elements or return ();
  my @links;
  foreach my $element (@{$elements}) {
    if ($element->isa('Netscape::Bookmarks::Link')) {
      push @links, new Bibliotech::Import::FirefoxBookmarks::Entry::Citation ($element, $category_path_titles_ref);
    }
    elsif ($element->isa('Netscape::Bookmarks::Category')) {
      push @links, $self->parse_category([@{$category_path_titles_ref}, $element->title], $element);
    }
  }
  return @links;
}

package Bibliotech::Import::FirefoxBookmarks::Entry;
use strict;
use base 'Bibliotech::Import::Entry::FromData';

sub raw_keywords {
  shift->data->keywords;
}

package Bibliotech::Import::FirefoxBookmarks::Entry::Citation;
use strict;
use base ('Netscape::Bookmarks::Link', 'Bibliotech::CitationSource::Result');
use HTML::Entities;

sub new {
  my ($class, $netscape_link, $keywords) = @_;
  my $self = bless $netscape_link, ref($class) || $class;
  $self->{__keywords} = $keywords;
  return $self;
}

sub type {
  'Firefox Bookmark';
}

sub source {
  'Firefox Bookmarks Upload';
}

sub uri {
  shift->href;
}

sub title {
  decode_entities(shift->SUPER::title);
}

sub description {
  decode_entities(shift->SUPER::description);
}

sub keywords {
  my $self = shift;
  my $keywords = $self->{__keywords} or return ();
  return map(decode_entities($_), @{$keywords});
}

1;
__END__
