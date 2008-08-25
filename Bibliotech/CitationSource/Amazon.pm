# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::Amazon class retrieves citation data for books
# on Amazon.com.

package Bibliotech::CitationSource::Amazon;

use strict;
use warnings;

use Bibliotech::CitationSource;
use base 'Bibliotech::CitationSource';
use Bibliotech::CitationSource::Simple;
use Bibliotech::DBI::Citation::Identifier;

sub api_version {
  1;
}

sub name {
  'Amazon';
}

sub version {
  '1.3';
}

sub understands {
  my ($self, $uri) = @_;
  $self->awsid or return 0;
  my $scheme = $uri->scheme or return 0;
  return 1 if $scheme =~ /^(?:asin|isbn)$/i;
  return 1 if $scheme eq 'info' and $uri->path =~ m!^(?:asin|isbn)/!;
  return 0 unless $uri->scheme eq 'http';
  return 0 unless $uri->host =~ m/^(?:www\.)?amazon\.(?:com|co\.uk|de|fr|co\.jp|ca)$/;
  return 0 unless $uri->path =~ m!/\d{9}(?:\d|X)(?:/|$)!i;
  return 1;
}

sub understands_id {
  my ($self, $id_hashref) = @_;
  return 0 unless $id_hashref and ref $id_hashref;
  my $db = $id_hashref->{db} or return 0;
  return 0 unless lc($db) eq 'amazon';
  my $id = $id_hashref->{asin} || $id_hashref->{isbn} or return 0;
  return 0 unless Bibliotech::Citation::Identifier::ASIN->validate($id);
  return 1;
}

sub _uri_from_asin {
  Bibliotech::Citation::Identifier::ASIN->new(shift)->uri;
}

sub filter {
  my ($self, $uri) = @_;
  return unless $uri;
  return _uri_from_asin($uri->opaque)                                      if $uri->scheme =~ /^(?:asin|isbn)$/i;
  return _url_from_asin(do { $uri->path =~ m!^(?:asin|isbn)/(.*)$!; $1; }) if $uri->scheme eq 'info';
  return;
}

sub citations {
  my ($self, $uri) = @_;
  my ($asin, $locale) = _amazon_uri_to_asin_and_locale($uri);
  die 'no ASIN' unless $asin;
  return $self->citations_id({db => 'amazon', asin => $asin}, $locale);
}

sub citations_id {
  my ($self, $id_hashref, $locale) = @_;
  my $asin = $id_hashref->{asin} || $id_hashref->{isbn} or die 'no ASIN provided';
  my $meta_uri = _amazon_asin_to_meta_uri($asin, $locale, $self->awsid)
      or $self->errstr('Unable to construct AWS URI for '.$asin), return;
  my $meta_xml = $self->content_or_set_errstr(sub { $self->get($meta_uri) }) or return;
  my $raw_citation = _raw_parse_amazon_xml($meta_xml);
  $raw_citation->{'title'} && $raw_citation->{'authors'}
      or $self->errstr('Insufficient metadata extracted for '.$asin), return;
  return Bibliotech::CitationSource::ResultList->new(Bibliotech::CitationSource::Result::Simple->new($raw_citation));
}

sub _amazon_uri_to_asin_and_locale {
  my $uri = pop or return;
  my ($locale) = ($uri->host =~ m!^(?:www\.)?amazon(.+)$!)  or return;
  my ($asin)   = ($uri->path =~ m!/(\d{9}(?:\d|X))(?:/|$)!) or return;
  return ($asin, $locale || 'www.amazon.com');
}

sub _amazon_asin_to_meta_uri {
  my ($asin, $locale, $awsid) = @_;
  return URI->new('http://webservices.amazon'.$locale.
		  '/onca/xml?Service=AWSECommerceService&SubscriptionId='.$awsid.
		  '&Operation=ItemLookup&IdType=ASIN&ItemId='.$asin.'&ResponseGroup=Small');
}

sub _raw_parse_amazon_xml {
  my $xml = shift;
  my $citation;
  my @items = ($xml =~ m!<Item>(.*?)</Item>!sg);
  if (@items == 1) {
    $citation->{'asin'}  = $1 if $items[0] =~ m/<ASIN>(.+?)<\/ASIN>/s;
    $citation->{'title'} = $1 if $items[0] =~ m/<Title>(.+?)<\/Title>/s;
    while($items[0] =~ m/<Author>(.+?)<\/Author>/sg) {
      push @{$citation->{'authors'}}, $1;
    }
    # try Creator if no Author
    unless ($citation->{'authors'}) {
      while ($items[0] =~ m/<Creator.*?>(.+?)<\/Creator>/sg) {
	push @{$citation->{'authors'}}, $1;
      }
    }
  }
  return $citation;
}

sub awsid {
  shift->cfg('AWSID');
}

1;
__END__
