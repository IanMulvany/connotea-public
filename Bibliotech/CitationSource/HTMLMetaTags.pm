# Copyright 2007 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::HTMLMetaTags class retrieves
# citation data for HTML pages with citation meta tags.
#
# Supports at least:
#   oxfordjournals.org
#   content.nejm.org
#   content.onlinejacc.org

package Bibliotech::CitationSource::HTMLMetaTags;
use strict;
use base 'Bibliotech::CitationSource';
use HTML::Parser ();
use Bibliotech::DBI;
use Bibliotech::Util;
use Bibliotech::CitationSource::Simple;

sub api_version {
  1;
}

sub name {
  'HTMLMetaTags';
}

sub version {
  '1.0';
}

# simple regex on the document being bookmarked, return 0 or 2
sub understands {
  my ($self, $uri, $content_sub) = @_;
  $uri->scheme eq 'http'      or return 0;
  local $_ = $content_sub->() or return 0;
  /<meta name=\"citation_/i   or return 0;
  return 2;
}

# put together a citation model
sub citations {
  my ($self, $uri, $content_sub) = @_;
  return undef unless $self->understands($uri, $content_sub);
  my ($response, $content, $title) = $content_sub->();
  my $last_modified_raw = scalar($response->header('Last-Modified')) ||
                          scalar($response->header('Date')) ||
                          Bibliotech::Util::now()->mysql_datetime;
  Bibliotech::CitationSource::ResultList->new
      (_citation_object(_citation_meta_tags($content), $last_modified_raw));
}

# in: HTML string
# out: arrayref of arrayrefs two fields apiece: [meta_tag_name, meta_tag_content]
# meta_tag_name will be lowercase, and the array is limited to citation meta tags
# meta_tag_content is already unescaped by HTML::Parser
# if content="..." is missing then meta_tag_content will be undef
sub _citation_meta_tags {
  my $html = shift or return;
  my @citation_meta;
  my $new_tag = sub { my $html_tag = shift or return;
		      return unless $html_tag eq 'meta';
		      my $attr_ref = shift or return;
		      my %attr = %{$attr_ref} or return;
		      my $name = $attr{name} or return;
		      my $key = lc($name);
		      return unless $key =~ /^(citation|dc\.)/;
		      my $value = $attr{content};
		      push @citation_meta, [$key => $value];
		      return; };
  my $parser = HTML::Parser->new(api_version => 3, start_h => [$new_tag, 'tag,attr']);
  $parser->parse($html);
  $parser->eof;
  return Bibliotech::CitationSource::HTMLMetaTags::MetaTags->new(\@citation_meta);
}

sub _citation_object {
  my ($meta, $last_modified_raw) = @_;
  Bibliotech::CitationSource::Result::Simple->new
      ({type   	=> 'HTML Meta Tags',
	source 	=> 'HTML of Bookmark',
	doi    	=> $meta->one_or_undef('citation_doi'),
	pubmed 	=> $meta->one_or_undef('citation_pmid'),
	title  	=> $meta->one_or_undef('citation_title'),
	volume 	=> $meta->one_or_undef('citation_volume'),
	issue  	=> $meta->one_or_undef('citation_issue'),
	page    => $meta->one_or_undef('citation_firstpage'),
	pubdate => Bibliotech::Date->new($meta->one_or_undef('citation_date') || $last_modified_raw)->ymd,
	authors => do { local $_ = $meta->one_or_undef('citation_authors') || ''; [split(/;\s*/)]; },
	journal => {name => $meta->one_or_undef('citation_journal_title'),
		    issn => $meta->one_or_undef('citation_issn')},
       });
}

package Bibliotech::CitationSource::HTMLMetaTags::MetaTags;

sub new {
  my ($class, $meta_ref) = @_;
  my $self = [@{$meta_ref}];
  return bless $self, ref $class || $class;
}

sub collect {
  my $self = shift;
  my %seen;
  my @result = map {
    my $key = $_;
    grep { !$seen{$_}++ } map { $_->[1] } grep { $_->[0] eq $key } @{$self};
  } @_;
  return wantarray ? @result : $result[0];
}

sub one_or_undef {
  my ($self, $key) = @_;
  my $value = $self->collect($key);
  return $value;
}

1;
__END__
