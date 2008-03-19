# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::BmcPdf class retrieves citation data for PDF articles
# on biomedcentral.com by converting to the abstanct URL and deferning to the autodiscovery plug-in

package Bibliotech::CitationSource::BmcPdf;

use strict;
use warnings;

use Bibliotech::CitationSource;
use base 'Bibliotech::CitationSource';

use Bibliotech::CitationSource::Simple;
use Bibliotech::CitationSource::autodiscovery;

sub api_version
{
  1;
}

sub name
{
  'BmcPdf';
}

sub version
{
  '1.1.2.1';
}

sub potential_understands {
  2;
}

sub understands
{
    my ($self, $uri) = @_;

	return 0 unless ($uri->scheme =~ /^http$/i);

	# check it looks like a BMC PDF
        return 0 unless ($uri->path =~ m/^\/content\/pdf\/.*\.pdf$/);
	
	# might be able to do something, so return 2
	return 2;	     
}

sub citations
{
	my ($self, $uri) = @_;

	return undef unless $self->understands($uri);
	
	#translate to abstract URL
	if ($uri->path =~ m/^\/content\/pdf\/(.+?-.+?)-(.+?)-(.+?)\.pdf$/) {
	    my $abs_html_url = 'http://' . $uri->host . '/';
	    #differnt rules for non-BMC.com hosts
	    my ($one, $two, $three) = ($1, $2, $3);
	    if ($uri->host =~ m/^(www\.)?biomedcentral\.com$/) {
		$abs_html_url .= $one . '/' . $two . '/' . $three . '/abstract';
	    }
	    else {
		$abs_html_url .= 'content/' . $two . '/1/' . $three . '/abstract';
	    }

	    my $ad = Bibliotech::CitationSource::autodiscovery->new($self->bibliotech);
	    return $ad->citations(URI->new($abs_html_url));
	}
	else {
	    $self->errstr("Couldn't convert PDF URL to abstract HTML URL");
	    return undef
	}
	
}

#true!
1;
