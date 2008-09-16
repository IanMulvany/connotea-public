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
  '1.13';
}

sub understands {
  my ($self, $uri) = @_;
  return 0 unless $uri->scheme eq 'http';
  return 0 unless $uri->host =~ /^(www\.)?nature.com$/;
  # new, e.g.: http://www.nature.com/ncpuro/journal/vaop/ncurrent/pdf/ncpuro1146.pdf
  return 1 if _article_path_to_metadata($uri->path);
  # old, e.g.: http://www.nature.com/cgi-taf/DynaPage.taf?file=/emboj/journal/v18/n17/full/7591878a.html&filetype=pdf
  return 1 if $uri->path eq '/cgi-taf/DynaPage.taf' && _article_path_to_metadata($uri->query_param('file'));
  return 0;
}

sub filter {
  my ($self, $orig_uri) = @_;
  my $uri = $orig_uri->clone;
  $uri->query_param_delete('_UserReference');  # always drop
  $uri->query_param_delete('filetype') unless $uri->query_param('filetype');  # drop if empty
  return $uri->eq($orig_uri) ? undef : $uri;
}

# note this does NOT match /news paths; or the index pages of journals, only their articles
sub _article_path_to_metadata {
  local $_ = shift or return ();
  m!^/([a-z]+)/journal/v(\d+|(?:aop))/n(\d+s?|(?:current))/(?:full|abs|pdf)/(.+?)(?:_[a-z]+)?\.(?:html|pdf)!i or return ();
  return ($1, $2, $3, $4);  # journal abbreviation, volume, issue, UID
}

sub _two_tries {
  my ($action, $delay) = @_;
  unless ($action->()) {
    sleep($delay || 1);
    $action->();
  }
}

sub citations {
  my ($self, $article_uri) = @_;
  my $ris;
  eval {
    my $path = $article_uri->query_param('file') || $article_uri->path or die "no file name seen in URI\n";
    my ($abr, $vol, $iss, $uid) = _article_path_to_metadata($path) or die "path not recognized ($path)\n";
    my $query_uri = URI->new("http://www.nature.com/$abr/journal/v$vol/n$iss/ris/$uid.ris");
    # give it two tries because nature.com is flakey
    # the NPG servers occasionally report 404 or 501 for no reason, or an empty 200
    _two_tries(sub { my $raw = $self->get($query_uri);
		     $ris = Bibliotech::CitationSource::RIS->new($raw);
		     defined $ris && $ris->has_data }, 2);
    die "RIS obj false: $query_uri\n" unless $ris;
    die "RIS file contained no data: $query_uri\n" unless $ris->has_data;
  };
  if (my $e = $@) {
    if ($e =~ /^RIS/) {
      $self->warnstr($e);  # level 1 error
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
