# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Import::Text class provides an import interface for
# simple text files of hyperlinks, including round-trip support for
# /plain output (minus user because you can't post as someone else).

package Bibliotech::Import::Text;
use strict;
use base 'Bibliotech::Import';
use Bibliotech::Const;

sub name {
  'Plain Text (one URL and tags per line)';
}

sub version {
  1.0;
}

sub api_version {
  1;
}

sub mime_types {
  (TEXT_MIME_TYPE);
}

sub extensions {
  ('txt', 'text');
}

sub noun {
  'text';
}

sub understands {
  $_[1] =~ /^(?:\w+ -> )?(?:\w{1,10}:|\d+$|\d+\s+\[?\"?\w)/mi ? 2 : 0;
}

sub parse {
  my $self = shift;
  $self->data(Bibliotech::Import::EntryList->new(map { Bibliotech::Import::Text::Entry->new($_) }
						 grep { $_ && !/^#/ }
						 split(/\n/, $self->doc)));
  return 1;
}

package Bibliotech::Import::Text::Entry;
use strict;
use base 'Bibliotech::Import::Entry::FromData';
use Bibliotech::CitationSource::Text;

sub parse {
  my ($self, $importer) = @_;
  my $block = $self->block or die 'no block';
  my $text_parser = Bibliotech::CitationSource::Text->new($block) or die 'no Text parser';
  my $noun = $importer->noun;
  my $text_result = $text_parser->make_result($noun, $noun.' Import');
  $self->data($text_result);
  $self->parse_ok(1);
  return 1;
}

sub keywords {
  ([Set::Array->new(shift->data->keywords)->flatten], []);
}

1;
__END__
