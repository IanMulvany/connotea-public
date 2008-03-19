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

# simple regex on the document being bookmarked
sub understands {
  my ($self, $uri, $content_sub) = @_;
  $uri->scheme eq 'http'      	     or return 0;
  local $_ = $content_sub->() 	     or return 0;
  /<meta name=\"(?:citation_|dc\.)/i or return 0;
  return 4;
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
# out: MetaTags object (see below)
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
		      my %others = %attr;
		      delete $others{name};
		      delete $others{content};
		      push @citation_meta, [$key => $value, \%others];
		      return; };
  HTML::Parser->new(api_version => 3, start_h => [$new_tag, 'tag,attr'])->parse($html)->eof;
  return Bibliotech::CitationSource::HTMLMetaTags::MetaTags->new
      (map { Bibliotech::CitationSource::HTMLMetaTags::MetaTag->new(@{$_}) } @citation_meta);
}

sub _citation_object {
  my ($meta, $last_modified_raw) = @_;
  Bibliotech::CitationSource::Result::Simple->new
      ({type   	=> 'HTML Meta Tags',
	source 	=> 'HTML of Bookmark',
	doi    	=> $meta->grep_key('citation_doi')->first_value ||
                   $meta->grep_key('dc.identifier')->grep_type_or_value(qr(doi)i, qr(^10\.))->first_value,
	pubmed 	=> $meta->grep_key('citation_pmid')->first_value ||
	           $meta->grep_key('dc.identifier')->grep_type_or_value(qr(^(pmid|pubmed)$)i, qr(^\d+$))->first_value,
	title  	=> $meta->grep_key('citation_title')->first_value ||
	           $meta->grep_key('dc.title')->first_value,
	volume 	=> $meta->grep_key('citation_volume')->first_value,
	issue  	=> $meta->grep_key('citation_issue')->first_value,
	page    => $meta->grep_key('citation_first_valuepage')->first_value,
	pubdate => Bibliotech::Date->new($meta->grep_key('citation_date')->first_value ||
					 $meta->grep_key('dc.date')->first_value ||
					 $last_modified_raw)->ymd,
	authors => do { local $_ = $meta->grep_key('citation_authors')->first_value;
			$_ ? [split(/;\s*/)] : $meta->grep_key('dc.creator')->values_arrayref; },
	journal => do { local $_ = $meta->grep_key('citation_journal_title')->first_value;
			$_ ? {name => $_,
			      issn => $meta->grep_key('citation_issn')->first_value} : undef; },
       });
}

package Bibliotech::CitationSource::HTMLMetaTags::MetaTags;

sub new {
  my $class = shift;
  my $self = [@_];
  return bless $self, ref $class || $class;
}

sub grep_key {
  my ($self, $key) = @_;
  return $self->new(grep { $_->key =~ $key } @{$self}) if ref($key) eq 'Regexp';
  return $self->new(grep { $_->key eq $key } @{$self});
}

sub grep_type {
  my ($self, $type) = @_;
  return $self->new(grep { $_->type =~ $type } @{$self}) if ref($type) eq 'Regexp';
  return $self->new(grep { $_->type eq $type } @{$self});
}

sub grep_value {
  my ($self, $value) = @_;
  return $self->new(grep { $_->value =~ $value } @{$self}) if ref($value) eq 'Regexp';
  return $self->new(grep { $_->value eq $value } @{$self});
}

sub grep_type_or_value {
  my ($self, $type, $value) = @_;
  my $result = $self->grep_type($type);
  return $result if @{$result};
  return $self->grep_value($value);
}

sub first {
  my $self = shift;
  return unless @{$self};
  return $self->[0];
}

sub first_value {
  my $self = shift;
  my $first = $self->first or return undef;
  return $first->value;
}

sub values_arrayref {
  my $self = shift;
  return [map { $_->value } @{$self}];
}

package Bibliotech::CitationSource::HTMLMetaTags::MetaTag;

sub new {
  my ($class, $key, $value, $attr) = @_;
  return bless [$key, $value, $attr], ref $class || $class;
}

sub key {
  shift->[0];
}

sub value {
  shift->[1];
}

sub attr {
  shift->[2];
}

sub type {
  my $attr = shift->attr or return;
  return $attr->{type};
}

1;
__END__
