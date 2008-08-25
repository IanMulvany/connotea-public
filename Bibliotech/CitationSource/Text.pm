# Copyright 2008 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::Text class interprets simple lines
# of text that contain a URL and some tags.

package Bibliotech::CitationSource::Text;
use strict;
use base 'Class::Accessor::Fast';
use URI;
use Bibliotech::Parser;

__PACKAGE__->mk_accessors(qw/line username uri tags/);

sub new {
  my ($class, $line) = @_;
  my $self = $class->SUPER::new({line => $line});
  $self->parse;
  return $self;
}

sub _split_tag_list {
  local $_ = shift or return ();
  return Bibliotech::Parser->new->tag_list($_);
}

sub _parse_text {
  local $_ = shift or return;
  return if m/^#/;                                # skip hash-prefixed comment lines
  my ($username, $uri, $tag_list) =
      m/^(?:(\w+)\s+->\s+)?                       # optionally, a username followed by an arrow
         ((?:\w{1,10}:\s+)?\S+)                   # URL or psuedo-URL with embedded space e.g. 'PMID: 12345'
         (?:\s+\[?([^\[\]]*)                      # tags, optionally surrounded by square brackets
           (?:\](?:\s+\#.*)?)?)?$                 # with tags, optionally, a hash-prefixed final comment
       /x or return;
  return ($username || undef, $uri || undef, $tag_list || undef);
}

sub _parse {
  local $_ = shift or return;
  my ($username, $uri, $tag_list) = _parse_text($_) or return;
  return ($username || undef,
	  URI->new(do { local $_ = $uri; s/^(\w{1,10}:)\s+/$1/; $_ }) || undef,
	  _split_tag_list($tag_list) || undef);
}

sub parse {
  my $self = shift;
  my ($username, $uri, @tagnames) = _parse($self->line);
  $self->username($username);
  $self->uri($uri);
  $self->tags(\@tagnames);
  return $self;
}

sub make_result {
  my ($self, $type, $source) = @_;
  bless $self, 'Bibliotech::CitationSource::Text::Result';
  $self->type($type);
  $self->source($source);
  return $self;
}

package Bibliotech::CitationSource::Text::Result;
use Bibliotech::CitationSource;
use base ('Bibliotech::CitationSource::Text', 'Bibliotech::CitationSource::Result', 'Class::Accessor::Fast');

__PACKAGE__->mk_accessors(qw/type source/);

sub make_resultlist {
  my $self = shift;
  return bless [$self], 'Bibliotech::CitationSource::ResultList';
}

sub keywords {
  shift->tags;
}

1;
__END__
