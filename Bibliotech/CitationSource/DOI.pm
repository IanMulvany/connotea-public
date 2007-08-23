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

use Data::Dumper;
use XML::LibXML;
use HTML::Entities;
use URI::Escape;
use constant CR_URL => 'http://doi.crossref.org/servlet/query';

sub api_version
{
  1;
}

sub name
{
  'DOI';
}

sub version
{
  '1.9.2.4';
}

sub understands
{
    my ($self, $uri) = @_;

    #reset query result cache
    $self->{'query_result'} = undef;

    return 0 unless $self->crossref_account;

    my $scheme = $uri->scheme;
    return 1 if $scheme eq 'doi';
    return 1 if $scheme eq 'http' and $uri->host eq 'dx.doi.org' && $uri->path =~ m!^/10\.\d{4}/.+!;
    return 0;
}

sub filter
{
  my ($self, $uri) = @_;
  my $doi = $self->get_doi($uri) or return undef;
  # Do the CrossRef query now so we can fail and return a nice error message if the DOI is not registered
  if (!$self->resolved($doi)) {
    $self->errstr("DOI $doi cannot be resolved.  It may not be in the CrossRef database, or you may have mis-entered it.  Please check it and try again.\n");
    return '';
  }
  $doi =~ s!\#!\%23!g;  # in case doi contains a hash
  my $canonical = URI->new('http://dx.doi.org/'.$doi);
  return undef if $canonical->eq($uri);
  return $canonical;
}

sub citations
{
     my ($self, $uri) = @_;
     return undef unless($self->understands($uri));
     
     my $doi = $self->get_doi($uri);
     return undef unless $doi;

     my $query_result = $self->query_result($doi);
     return undef unless $query_result;

     #check it's worth returning
     unless($query_result->{'journal'} && $query_result->{'pubdate'})
     {
	$self->errstr('Insufficient metadata extracted for doi:' . $doi);
	return undef;
     }

     return new Bibliotech::CitationSource::ResultList(Bibliotech::CitationSource::Result::Simple->new($query_result));
}


sub resolved
{
    my ($self, $doi) = @_;
    my $query_result = $self->query_result($doi);

    return 1 if $query_result->{'status'} && $query_result->{'status'} eq 'resolved';
    return 0;
}
sub query_result
{
    my ($self, $doi) = @_;
    return $self->{'query_result'}->{$doi} if $self->{'query_result'}->{$doi};
    my $xml = $self->crossref_query_uri($doi); 
    my $query_result = $self->parse_crossref_xml($xml, $doi);
    return undef unless $query_result;
    $self->{'query_result'}->{$doi} = $query_result;
    return $query_result;
}

sub parse_crossref_xml
{
    my ($self, $xml, $doi) = @_;
    return undef unless $xml;
    $xml =~ s/<crossref_result.*?>/<crossref_result>/;

    my $parser = XML::LibXML->new();
    my $tree = $parser->parse_string($xml);
    unless ($tree) {
		$self->errstr('XML parse failed');
		return undef;
    }

    my $root = $tree->getDocumentElement;
    unless ($root) {
		$self->errstr("no root");
    }


    #sanity check
    unless(lc($root->findvalue('query_result/body/query/doi')) eq lc($doi)) {
		$self->errstr("DOI mismatch\n");
		return undef;
    }
    return { status => 'unresolved' } if $root->findvalue('query_result/body/query/@status') eq 'unresolved';	

    #CrossRef XML has double-encoded entities, hence the decode_entities below

    return {
             status => 'resolved',
	     pubdate => $self->get_QueryValue($root, 'year'),
             journal => { name => decode_entities($self->get_QueryValue($root, 'journal_title')), 
                          issn => $self->get_QueryValue($root, 'issn[@type="print"]') 
			}, 
	     page => $self->get_QueryValue($root, 'first_page'), 
             volume => $self->get_QueryValue($root, 'volume'),
             issue => $self->get_QueryValue($root, 'issue'),
             pubdate => $self->get_QueryValue($root, 'year'),
             title => decode_entities($self->get_QueryValue($root, 'article_title')), 
             doi => $doi
        }; 
}

sub get_QueryValue {
  my ($self, $root, $key) = @_;
    
	
  my $value;
  $value = $root->findvalue('query_result/body/query/' . $key); 
  unless ($value) {
    #$self->errstr("No value for key: $key\n");
    return undef;
  }
  return $value;
}

sub get_doi {
    my ($self, $uri) = @_;
    my $doi;
    if($uri->scheme eq 'doi') {
	$doi = $uri;
	$doi =~ s!^doi:!!;
    }
    elsif ( $uri->scheme eq 'http' && $uri->host eq 'dx.doi.org' && $uri->path =~ m!^/10\.\d{4}/.+! ) {
        #DOI may contain a hash, so just manipulate raw string
        $doi = $uri->as_string;
        $doi =~ s!^http://dx\.doi\.org/!!i;
	#$doi = $uri->path;
	#$doi =~ s!^/!!;
    }
    #URI module escapes unsafe characters 
    return lc(uri_unescape($doi));
}


sub crossref_query_uri {
    my ($self, $doi) = @_;

    my ($user, $passwd) = $self->crossref_account;
	my $ua = $self->ua;
	my $req = new HTTP::Request(POST => CR_URL);
	my $db = 'db=mddb';

	my $content = "usr=" . $user . "&pwd=" . $passwd . "&$db&report=Brief&format=XSD_XML&qdata=";
	$content .= uri_escape($self->build_query($doi));

	$req->content_type('application/x-www-form-urlencoded');
	$req->content($content);

	#set timeout 
	$ua->{timeout} = 900;

	my $response = $ua->request($req);
	my($headers) = $response->headers;


	if($response->is_success) {
			my($results) = $response->content;

			#
			# trap error message from crossref
			#       where there are data errors
			#       dump to browser
			#
			if($headers->title) {
					$self->errstr($headers->title . "\n");
					$self->errstr ($results);
					return undef;
			}

			return($results);
	}

	$self->errstr("WARNING: " . $response->status_line . "\n");
	return undef;
}

sub build_query {

    my ($self, $doi) = @_;
    $doi = encode_entities($doi);
    my $q = q{<?xml version = "1.0" encoding="UTF-8"?>
<query_batch version="2.0" xmlns = "http://www.crossref.org/qschema/2.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
   <head>
      <email_address>};
    $q .= $self->bibliotech->siteemail;
    $q .= q{</email_address>
      <doi_batch_id>DOI-B1</doi_batch_id>                  
   </head>
   <body>
      <query key="MyKey1" enable-multiple-hits="false" expanded-results="true">         
  };
  $q .= "<doi>\n    $doi\n    </doi>\n";
  $q .= q{</query>      
   </body>
</query_batch>  };
  return $q;
}

sub crossref_account {
    my ($self) = shift;
    my $user = $self->cfg('CR_USER');
    my $password = $self->cfg('CR_PASSWORD');

    ($user && $password) ? return ($user, $password) : return undef;
}

#true!
1;
