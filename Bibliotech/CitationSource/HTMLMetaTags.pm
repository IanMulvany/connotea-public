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

sub potential_understands {
  4;
}

# simple regex on the document being bookmarked
sub understands {
  my ($self, $uri, $content_sub) = @_;
  $uri->scheme eq 'http'      or return 0;
  local $_ = $content_sub->() or return 0;
  /<meta\s+name=\"(?:citation_|dc\.\w+|prism\.\w+)\"\s/i or return 0;
  return 4;
}

# put together a citation model
sub citations {
  my ($self, $uri, $content_sub) = @_;
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
  my @citation_meta;  # will be populated by calls to &$parse_one_tag from HTML::Parser
  my $parse_one_tag = sub { my $html_tag = shift or return;
			    return unless $html_tag eq 'meta';
			    my $attr_ref = shift or return;
			    my %attr = %{$attr_ref} or return;
			    my $name = delete($attr{name}) or return;
			    return unless $name =~ /^(citation|dc\.|prism\.)/i;
			    my $value = delete($attr{content});
			    my $type = delete($attr{type}) || delete($attr{scheme});
			    push @citation_meta, [lc($name), $value, lc($type), \%attr];
			    return; };
  HTML::Parser->new(api_version => 3, start_h => [$parse_one_tag, 'tag,attr'])->parse($html)->eof;
  return Bibliotech::CitationSource::HTMLMetaTags::MetaTags->new(@citation_meta);
}

sub _citation_object {
  my ($meta, $last_modified_raw) = @_;
  Bibliotech::CitationSource::Result::Simple->new
      ({type   	=> 'HTML Meta Tags',
	source 	=> 'HTML of Bookmark',
	doi    	=> _without_prefix
	           ($meta->grep_key('citation_doi')->first_value ||
		    $meta->grep_key('dc.identifier')->grep_type_or_value(qr(doi)i,
									 qr(^(?:doi: ?)?10\.\d+\/)i)->first_value),
	pubmed 	=> _without_prefix
	           ($meta->grep_key('citation_pmid')->first_value ||
		    $meta->grep_key('dc.identifier')->grep_type_or_value(qr(^(?:pm|pmid|pubmed)$)i,
									 qr(^(?:(?:pm|pmid|pubmed): ?)\d+$)i)->first_value),
	asin 	=> _without_prefix
	           ($meta->grep_key('citation_isbn')->first_value ||
		    $meta->grep_key('dc.identifier')->grep_type_or_value(qr(^(?:isbn|asin)$)i,
									 qr(^(?:(?:isbn|asin): ?))i)->first_value),
	identifiers => do { my @others =
				$meta->grep_key('dc.identifier')->grep_not_type_or_value
				(qr(^(?:doi|pm|pmid|pubmed|isbn|asin)$)i,
				 qr(^(?:doi|pm|pmid|pubmed|isbn|asin): ?)i)
				->type_values_array;
			    my %others = map { my ($type, $value) = @{$_};
					       $value =~ s/^([A-za-z]+): ?//;
					       my $key = $type || $1;
					       $key => $value; } @others;
			    %others ? \%others : undef; },
	title  	=> $meta->grep_key('citation_title')->first_value ||
	           $meta->grep_key('dc.title')->first_value,
	volume 	=> $meta->grep_key('citation_volume')->first_value ||
                   $meta->grep_key('prism.volume')->first_value,
	issue  	=> $meta->grep_key('citation_issue')->first_value ||
                   $meta->grep_key('prism.number')->first_value ||
	           $meta->grep_key('prism.issueidentifier')->first_value,
	page    => $meta->grep_key('citation_first_valuepage')->first_value ||
                   do { my $sp = $meta->grep_key('prism.startingPage')->first_value;
			my $ep = $meta->grep_key('prism.endingPage')->first_value;
			$sp ? ($ep ? $sp.' - '.$ep : $sp) : undef; },
	pubdate => Bibliotech::Date->new($meta->grep_key('citation_date')->first_value ||
					 $meta->grep_key('dc.date')->first_value ||
					 $meta->grep_key('prism.publicationdate')->first_value ||
					 $meta->grep_key('prism.creationdate')->first_value ||
					 $last_modified_raw)->ymd,
	authors => do { local $_ = $meta->grep_key('citation_authors')->first_value;
			$_ ? [split(/;\s*/)] : $meta->grep_key('dc.creator')->values_arrayref; },
	journal => do { local $_ = $meta->grep_key('citation_journal_title')->first_value ||
			           $meta->grep_key('prism.publicationName')->first_value;
			$_ ? {name => $_,
			      issn => $meta->grep_key('citation_issn')->first_value ||
				      $meta->grep_key('prism.issn')->first_value} : undef; },
       });
}

sub _without_prefix {
  local $_ = shift or return undef;
  s/^[A-za-z]+: ?//;
  return $_;
}

package Bibliotech::CitationSource::HTMLMetaTags::MetaTags;

sub new {
  my $class = shift;
  my $self = [map { Bibliotech::CitationSource::HTMLMetaTags::MetaTag->new(@{$_}) } @_];
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

sub grep_type_not {
  my ($self, $type) = @_;
  return $self->new(grep { $_->type !~ $type } @{$self}) if ref($type) eq 'Regexp';
  return $self->new(grep { $_->type ne $type } @{$self});
}

sub grep_value_not {
  my ($self, $value) = @_;
  return $self->new(grep { $_->value !~ $value } @{$self}) if ref($value) eq 'Regexp';
  return $self->new(grep { $_->value ne $value } @{$self});
}

sub grep_not_type_or_value {
  my ($self, $type, $value) = @_;
  return $self->grep_type_not($type)->grep_value_not($value);
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

sub type_values_array {
  my $self = shift;
  return map { [$_->type => $_->value] } @{$self};
}

package Bibliotech::CitationSource::HTMLMetaTags::MetaTag;

sub new {
  my ($class, $key, $value, $type, $other_attr) = @_;
  return bless [$key, $value, $type, $other_attr], ref $class || $class;
}

sub key   { shift->[0] }
sub value { shift->[1] }
sub type  { shift->[2] }
sub attr  { shift->[3] }

1;
__END__
