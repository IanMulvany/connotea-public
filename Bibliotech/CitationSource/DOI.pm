# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::DOI class recognises DOIs
# in the URI-like doi: construction or as http://dx.doi.org/...
# URLs and queries CrossRef for the metadata.
#
# NOTE: This module relies on membership of CrossRef.  You must
# have a CrossRef web services query account and permission to
# use it for this purpose. More details via:
# http://www.crossref.org/ 

package Bibliotech::CitationSource::DOI;

use strict;
use warnings;

use Bibliotech::CitationSource;
use base 'Bibliotech::CitationSource';

use Bibliotech::CitationSource::Simple;

use XML::LibXML;
use HTML::Entities;
use URI::Escape;
use constant CR_URL => 'http://doi.crossref.org/servlet/query';

sub api_version {
  1;
}

sub name {
  'DOI';
}

sub version {
  '2.0';
}

sub understands {
  my ($self, $uri) = @_;
  $self->{'query_result'} = undef;  # reset query result cache
  return 0 unless $self->crossref_account;
  return 1 if $self->get_doi($uri);
  return 0;
}

sub filter {
  my ($self, $uri) = @_;
  my $doi = $self->get_doi($uri) or return undef;
  if (!$self->resolved($doi)) {  # do crossref query now, fail if doi unregistered
    $self->errstr("DOI $doi cannot be resolved.  It may not be in the CrossRef database, or you may have mis-entered it.  Please check it and try again.\n");
    return '';
  }
  $doi =~ s!\#!\%23!g;  # in case doi contains a hash
  my $canonical = URI->new('http://dx.doi.org/'.$doi);
  return undef if $canonical->eq($uri);
  return $canonical;
}

sub citations {
  my ($self, $uri) = @_;
  return undef unless $self->understands($uri);

  my $doi = $self->get_doi($uri);
  return undef unless $doi;

  my $query_result = $self->query_result($doi);
  return undef unless $query_result;

  #check it's worth returning
  unless($query_result->{'journal'} && $query_result->{'pubdate'}) {
    $self->errstr('Insufficient metadata extracted for doi:'.$doi);
    return undef;
  }

  return Bibliotech::CitationSource::ResultList->new(Bibliotech::CitationSource::Result::Simple->new($query_result));
}

sub resolved {
  my ($self, $doi) = @_;
  my $query_result = $self->query_result($doi);
  return 1 if defined $query_result && $query_result->{'status'} && $query_result->{'status'} eq 'resolved';
  return 0;
}

sub query_result {
  my ($self, $doi) = @_;
  return $self->{'query_result'}->{$doi} if $self->{'query_result'}->{$doi};
  return $self->{'query_result'}->{$doi} = $self->query_result_calc($doi);
}

sub query_result_calc {
  my ($self, $doi) = @_;
  return $self->parse_crossref_xml($self->crossref_query($doi), $doi) || undef;
}

sub parse_crossref_xml {
  my ($self, $xml, $doi) = @_;
  return unless $xml;

  $xml =~ s/<crossref_result.*?>/<crossref_result>/;

  my $tree = XML::LibXML->new->parse_string($xml)   or $self->errstr('XML parse failed'), return;
  my $root = $tree->getDocumentElement              or $self->errstr('no root'), return;
  my $node = 'query_result/body/query/';
  my $val  = sub { $root->findvalue($node.shift) };
  lc($val->('doi')) eq lc($doi)                     or $self->errstr("DOI mismatch\n"), return;

  return {status  => 'unresolved'} if $val->('@status') eq 'unresolved';
  return {status  => 'resolved',
	  pubdate => $val->('year') || undef,
	  journal => { name => decode_entities($val->('journal_title')) || undef,
		       issn => $val->('issn[@type="print"]') || undef},
	  page    => $val->('first_page') || undef,
	  volume  => $val->('volume') || undef,
	  issue   => $val->('issue') || undef,
	  pubdate => $val->('year') || undef,
	  title   => decode_entities($val->('article_title')) || undef,
	  doi     => $doi}; 
}

sub _get_raw_doi_from_uri {
  my $uri = shift;
  $uri =~ /^10\./ and return "$uri";
  my $scheme = $uri->scheme;
  local $_   = $uri->path;
  return $_                         if $scheme eq 'doi';
  return do { m|^doi/(.*)$|i; $1; } if $scheme eq 'info';
  return do { m|^/(.*)$|; $1; }     if $scheme eq 'http' and $uri->host eq 'dx.doi.org';
  return;
}

sub _clean_raw_doi_from_uri {
  my $doi = shift or return;
  $doi =~ s/^doi://i;  # sometimes repeated in dx.doi.org URL
  $doi =~ m/^10\./ or return;
  return lc(uri_unescape($doi));  # URI module escapes unsafe characters
}

sub get_doi {
  my ($self, $uri) = @_;
  return _clean_raw_doi_from_uri(_get_raw_doi_from_uri($uri));
}

sub _crossref_query_http_request {
  my ($user, $password, $query_xml) = @_;
  my $req = HTTP::Request->new(POST => CR_URL);
  $req->content_type('application/x-www-form-urlencoded');
  $req->content(join('&',
		     'usr='.$user,
		     'pwd='.$password,
		     'db=mddb',
		     'report=Brief',
		     'format=XSD_XML',
		     'qdata='.uri_escape($query_xml)));
  return $req;
}

sub crossref_query {
  my ($self, $doi) = @_;
  my $ua = $self->ua;
  my $response = $ua->request(_crossref_query_http_request($self->crossref_account, $self->build_query($doi)));
  $response->is_success or $self->errstr($response->status_line), return undef;
  return $response->content;
}

sub query_xml_template {
'<?xml version="1.0" encoding="UTF-8"?>
<query_batch version="2.0"
             xmlns="http://www.crossref.org/qschema/2.0"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <head>
    <email_address>__EMAIL__</email_address>
    <doi_batch_id>DOI-B1</doi_batch_id>
  </head>
  <body>
    <query key="MyKey1" enable-multiple-hits="false" expanded-results="true">
      <doi>__DOI__</doi>
    </query>      
  </body>
</query_batch>
';
}

sub build_query {
  my ($self, $doi) = @_;
  my $xml         = $self->query_xml_template;
  my $email       = $self->bibliotech->siteemail;
  my $escaped_doi = encode_entities($doi);
  $xml =~ s/__EMAIL__/$email/;
  $xml =~ s/__DOI__/$escaped_doi/;
  return $xml;
}

sub crossref_account {
  my $self     = shift;
  my $user     = $self->cfg('CR_USER')     or return;
  my $password = $self->cfg('CR_PASSWORD') or return;
  return ($user, $password);
}

1;
__END__
