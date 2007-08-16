# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::NPG class retrieves citation data for articles
# on Nature.com.

use strict;
use Bibliotech::CitationSource;

package Bibliotech::CitationSource::NPG;
use base 'Bibliotech::CitationSource';
use URI;
use URI::QueryParam;

sub api_version {
  1;
}

sub name {
  'Nature Publishing Group';
}

sub cfgname {
  'NPG';
}

sub version {
  '1.12.2.5';
}

sub understands {
  my ($self, $uri) = @_;

  return 0 unless $uri->scheme eq 'http';
  #check the host
  return 0 unless ($uri->host =~ /^(www\.)?nature.com$/);
  #old-style links
  return 1 if ($uri->path eq '/cgi-taf/DynaPage.taf' && $uri->query_param('file'));
  #new-style links
  return 1 if ($uri->path =~ m!^/[a-z]+?/journal/v(?:\d+|aop)/n(?:\d+|current)/(?:full|abs)/.+\.html!i);
  return 0;
}

sub filter {
  my ($self, $uri) = @_;
  $uri->query_param_delete('_UserReference');  # always drop
  $uri->query_param_delete('filetype') unless $uri->query_param('filetype');  # drop if empty
  return $uri;
}

sub citations {
  my ($self, $article_uri) = @_;

  my $ris;
  eval {
    die "do not understand URI\n" unless $self->understands($article_uri);

    my $file;
    #old-style link
    if(my $temp = $article_uri->query_param('file')) {
      $file = $temp;
    }
    #new-style link
    else {
	$file = $article_uri->path;
        #strip fragments or queries
        $file =~ s/\.html(?:#|\?).*/.html/;
    }

    die "no file name seen in URI\n" unless $file;
    my ($abr, $vol, $iss, $uid)
	= ($file =~ m!^/([a-z]+)/journal/v(\d+|(?:aop))/n(\d+|(?:current))/.+?/(.+?)(?:_[a-z]+)?\.html!i);
    die "no abbreviated journal name\n" unless $abr;
    die "no volume\n" unless $vol;
    die "no issue\n" unless $iss;
    die "no UID\n" unless $uid;
    my $query_uri = URI->new("http://www.nature.com/$abr/journal/v$vol/n$iss/ris/$uid.ris");

    my $ris_raw = $self->get($query_uri);
    $ris = Bibliotech::CitationSource::RIS->new($ris_raw);
    if (!$ris->has_data) {
      # give it one more try because nature.com is flakey
      # the NPG servers occasionally report 404 or 501 for no reason
      # additionally I think they sometimes return no data with a 200
      sleep 2;
      $ris_raw = $self->get($query_uri);
      $ris = Bibliotech::CitationSource::RIS->new($ris_raw);
    }
    die "RIS obj false: $query_uri\n" unless $ris;
    die "RIS file contained no data: $query_uri\n" unless $ris->has_data;
  };    

	if (my $e = $@) {
		if ($e =~ /^RIS/) {
				# Level 1 error
				$self->warnstr($e);
				return undef;
		}

		die $e if $e =~ /at .* line \d+/;  # perl error, bubble up
		$self->errstr($e);                 # report the other errors
		return undef;
	}

  return $ris->make_result('NPG', 'NPG RIS file from www.nature.com')->make_resultlist;
}

package Bibliotech::CitationSource::NPG::RIS;
use base 'Bibliotech::CitationSource::RIS';

1;
__END__
