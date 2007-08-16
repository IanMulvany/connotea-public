# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::PMC class retrieves citation data for articles
# on pubmedcentral.org using an open archives initiative protocol for metadata harvesting (OAI-PMH)

package Bibliotech::CitationSource::PMC;

use strict;
use warnings;

use Bibliotech::CitationSource;
use base 'Bibliotech::CitationSource';

use Bibliotech::CitationSource::Simple;

use Data::Dumper;
use XML::LibXML;
use XML::LibXML::NodeList;

use HTTP::OAI::Harvester;
use constant VERSION => '2.0'; 						# version for Harvester Identify
use constant PMC_BASE_URL => 'http://www.pubmedcentral.gov/oai/oai.cgi'; # baseURL for Harvester Identify
use constant META_PREFIX => 'pmc_fm';				# return metadata only
use constant ID_PREFIX => 'oai:pubmedcentral.gov';	# prefix for Harvester GetRecord() identifier

sub api_version
{
  1;
}

sub name
{
  'PMC';
}

sub version
{
  '1.5';
}

sub understands
{
    my ($self, $uri) = @_;

	#check the host
	return 0 unless ($uri->scheme =~ /^http$/i);
	return 0 unless ($uri->host =~ m/^(www\.)?pubmedcentral(\.nih)?\.(gov|org)$/);

	#check there's a query
	return 0 unless $uri->query;

	# check the path
	return 0 unless ($uri->path =~ m/articlerender\.fcgi/ || $uri->path =~ m/pagerender\.fcgi/ || ($uri->path =~ m/picrender\.fcgi/ && $uri->query =~ /blobtype=pdf/i));
	
	#finally, check the query for article page request
	return 1 if ($uri->query =~ m/artid=[0-9]+/);
	return 2 if ($uri->query =~ m/pubmedid=[0-9]+/);

    return 0;
}

sub citations
{
	my ($self, $uri) = @_;

	my $understands = $self->understands($uri);
	return undef unless $understands;

	if ($understands == 2) {
	  $uri->query =~ m/pubmedid=([0-9]+)/;
	  my %id = (db => 'pubmed', pubmed => $1);
	  return $self->citations_id_switch('Pubmed', \%id);
	}
     
	my $art_id = $self->get_art_id($uri);
	return undef unless $art_id;
	 
	my $metadata = $self->metadata($art_id);
	return undef unless $metadata;

	return new Bibliotech::CitationSource::ResultList(Bibliotech::CitationSource::Result::Simple->new($metadata));
}

#
# The PubMed Central OAI service (PMC-OAI) provides access to metadata of all items in the PubMed Central (PMC) archive, 
#	as well as to the full text of a subset of these items.
#
# Peak hours for requests are Monday to Friday, 5:00 AM to 9:00 PM, U.S. Eastern time. 
# Do not make more than one request every 3 seconds, even at off-peak times. 
#
sub metadata
{
    my ($self, $art_id) = @_;
    my $xml;

	#
	# harvest the PMC-OAI static repository with the Identify method, at baseURL 
	#	already know the Identify object
	#
	my $h = HTTP::OAI::Harvester->new(
		repository=>HTTP::OAI::Identify->new( baseURL=> PMC_BASE_URL, version=> VERSION)
	);

	#
	# get corresponding record for $art_id from repository
	#
	my($gr) = $h->GetRecord(
			#identifier => ID_PREFIX . ":" . "abc",		# to test for error (no match) from GetRecord
			identifier => ID_PREFIX . ":" . $art_id,	# required
			metadataPrefix => META_PREFIX				# required
	);

	# this didn't work
	#if($gr->is_error) {
		#$self->errstr('GetRecord Error: ' . $gr->message);
		#return undef;
	#}
	if($gr->errors) {
		$self->errstr('GetRecord Error for ' . $art_id);
		return undef;
	}

	#
	# get first record from GetRecord object (first record stored in response)
	#	??how likely will it be to have multiple records returned for an artid??
	#
	my($rec) = $gr->next;

	unless($rec) {
		$self->errstr("No records");
		return undef;
	}

	#
	# could be helpful
	#
	#$self->errstr($rec->identifier . " (" . $rec->datestamp . ")");

	# get the parsed DOM tree
	my($dom) = $rec->metadata->dom;

	###DEBUG
	#return $dom;
	
       # go get the metadata from tree
    my $metadata = $self->build_metadata($dom);
    return undef unless $metadata;

    # check that it's worth returning
    unless($metadata->{'journal'} && $metadata->{'pubdate'})
    {
		$self->errstr('Insufficient metadata extracted for artid: ' . $art_id);
		return undef;
    }

    return $metadata;
}

sub get_art_id {
    my ($self, $uri) = @_;

    my $art_id;

	my(%q_hash) = $uri->query_form;
	my($q_hash_ref) = \%q_hash;
    if ( $uri->scheme eq 'http' && keys %{$q_hash_ref} ) {
    	$art_id = $q_hash_ref->{'artid'};
    }
    return $art_id;
}

my @monthnames = ("", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");

sub build_metadata 
{
    my ($self, $dom) = @_;

    my $root = $dom->getDocumentElement;

	unless ($root) {
		$self->errstr("no root");
	}

	#
	# grab journal-meta node
	#
	my $jmeta = getFirstElement($root, 'journal-meta');
	my $journaltitle = getFirstElement($jmeta, 'journal-title');

	#		get print issue number
	my $issn = "";
	foreach my $i ($jmeta->getElementsByLocalName('issn')) {
		my $pubtype = $i->getAttribute('pub-type');
		if ($pubtype eq "ppub") {
			$issn = $i->string_value;
		}
	}
	
	#
	# now grab article-meta node
	#
	my $artmeta = getFirstElement($root, 'article-meta');
        my $title = getFirstElement($artmeta, 'article-title');
	my $fpage = getFirstElement($artmeta, 'fpage');
        my $lpage = getFirstElement($artmeta, 'lpage');
	my $vol = getFirstElement($artmeta, 'volume');
        my $issue = getFirstElement($artmeta, 'issue');

	#convert nodes to strings, checking for undef first.
	($journaltitle, $title, $fpage, $lpage, $vol, $issue) = map { $_->string_value if $_ } ($journaltitle, $title, $fpage, $lpage, $vol, $issue);

 	#sort out page range
	my $page;
	$page = $fpage if $fpage;
	$page = $fpage.' - '.$lpage if ($fpage && $lpage && ($fpage != $lpage));

	#get identifiers
	my $pmid;
	my $doi;

	foreach my $i ($artmeta->getElementsByLocalName('article-id')) {
                my $pubtype = $i->getAttribute('pub-id-type');
                if ($pubtype eq "pmid") {
                        $pmid = $i->string_value;
                }
		if ($pubtype eq "doi") {
                        $doi = $i->string_value;
                }

        }

 
	#		get  pub date
	my $day = '';
	my $month = '';
	my $year = '';
 	my ($pday, $pmonth, $pyear, $eday, $emonth, $eyear);

	foreach my $pd ($artmeta->getElementsByLocalName('pub-date')) {
		my $pubtype = $pd->getAttribute('pub-type');
		if ($pubtype eq "ppub") {
			$pday = getFirstElement($pd, 'day');
			$pmonth = getFirstElement($pd, 'month');
			$pyear = getFirstElement($pd, 'year');
		}
		if ($pubtype eq "epub") {
			$eday = getFirstElement($pd, 'day');
                        $emonth = getFirstElement($pd, 'month');
                        $eyear = getFirstElement($pd, 'year');
                }

	}
	my @pcount = grep { defined $_; } ($pday, $pmonth, $pyear);
        my @ecount = grep { defined $_; } ($eday, $emonth, $eyear);
	if (@ecount > @pcount) {
		$day = $eday->string_value if $eday;
                $month = $emonth->string_value if $emonth;
                $year = $eyear->string_value if $eyear;

	}
	else {
                $day = $pday->string_value if $pday;
                $month = $pmonth->string_value if $pmonth;
                $year = $pyear->string_value if $pyear;

	}

	#		get the author info
	my @contrib_groups = $artmeta->getElementsByLocalName('contrib-group');
	my($authors);
        $authors = &getAuthors(@contrib_groups) if @contrib_groups;
    return { 
             title => $title,
	     pubdate => "$day $monthnames[$month] $year",
         journal => { name => $journaltitle,
                      issn => $issn,
					}, 
		 page => $page,
         volume => $vol,
         issue => $issue,
         pubmed => $pmid,
	 doi => $doi,
         authors => $authors,
	};
}

sub getAuthors {
	my ($authorGroup) = @_;

	my(@auList);

	# build names foreach contrib that contrib-type = "author"
	foreach my $c ($authorGroup->getElementsByLocalName('contrib')) {
		my $type = $c->getAttribute('contrib-type');
		my $name;
		#  build name (others: collab)
		if(getFirstElement($c, 'name') && $type eq "author") {
			$name->{'forename'} = getFirstElement($c, 'given-names')->string_value;
			$name->{'lastname'} = getFirstElement($c, 'surname')->string_value;
		}

		push(@auList, $name) if $name;
	}
	return \@auList if @auList;
	return undef unless @auList;
	#return "No Authors" unless @auList;
}

#
# get the first element in the array returned by getElementsByLocalName
#
sub getFirstElement {
	my ($node, $name) = @_;
	my @values = $node->getElementsByLocalName($name);
	return($values[0]);
}

#sub errstr {
#    my ($self, $err) = @_;
#
#    print STDERR $self->name . " " . $err . "\n";
#}

#true!
1;
