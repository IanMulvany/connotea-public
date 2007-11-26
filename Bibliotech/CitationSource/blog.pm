# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::blog class retrieves citation data for blog entries in either RSS or Atom structure
#		1. parse the HTML of the URL, to get the link to the atom or rss feed (in <link> element) - used HTML::TokeParser for ease
#		2. read atom or rss feed (at url), parse with XML::Feed (built on XML::Atom::Feed or XML::RSS)
#		3. get citation data by looping through feed to find match with original URL
#

package Bibliotech::CitationSource::blog;
use strict;

use Bibliotech::CitationSource;
use base 'Bibliotech::CitationSource';

use Bibliotech::CitationSource::Simple;

use HTTP::Request::Common;	# request(GET xx);

use URI;
use URI::QueryParam;

use HTML::TokeParser;	# to parse HTML content
use XML::Feed;

sub api_version {
  1;
}

sub name {
  'Blogger';
}

sub cfgname {
  'blog';
}

sub version {
  '1.2.2.4';
}

sub understands {
  my ($self, $uri, $getURLContent_sub) = @_;

  return 0 unless $uri->scheme eq 'http';

  $self->clearContent;
  $self->warnstr('');

  my ($ok, $response) = $self->catch_transient_warnstr(sub { $self->getURLContent($getURLContent_sub || $uri) });
  $ok or return -1;

  my $content_type = $response->content_type;
  $content_type eq 'text/html' || $content_type eq 'application/xhtml+xml'
      or return 0;

  $self->{feedURL} = getFeedURL($response->content)
      or return 0;

  return 3;  # 3 is the code for success from this module
}

sub clearContent {
  my ($self) = @_;
  undef $self->{feedURL};
}

sub getURLContent {
  my ($self, $content_sub_or_uri) = @_;

  my $response = do {
    if (ref($content_sub_or_uri) eq 'CODE') {
      ($content_sub_or_uri->())[0];
    }
    else {
      scalar $self->ua->request(GET $content_sub_or_uri);
    }
  };

  # check for problems with request
  die $response->status_line."\n" unless $response->is_success;

  return $response;
}

#
# parse and load up the atom or rss <link> in the HTML file
#
sub getFeedURL {
  my $content = shift or return;
  my @candidate_urls;
  my $parser = HTML::TokeParser->new(\$content);
  while (my $token = $parser->get_tag('link')) {
    my $href = $token->[1]{href} or next;
    my $type = $token->[1]{type};
    my $rel  = $token->[1]{rel};
    return $href if $type eq 'application/atom+xml' && $rel eq 'alternate';  # use it if Atom
    push @candidate_urls, $href if $type =~ m,application/(rss|atom),i;      # otherwise store as possibility
  }
  return $candidate_urls[0];  # use the first candiate if we got this far
}

sub urlCheck {
  my($self, $uri, $url) = @_;

  #convert relative URL to absolute, if necessary
  my $new_url = URI->new_abs($url, $uri);
       
  #print "$url    --->    $new_url\n";

  return $new_url;
}

sub citations {
  my ($self, $blog_uri) = @_;

  my $metadata;
  eval {
    # in understands, see if header type html, and has atom or rss feed
    $self->errstr('do not understand URI'), return undef unless $self->understands($blog_uri);

    $self->{feedURL} = $self->urlCheck($blog_uri, $self->{feedURL}) if $self->{feedURL};

    # need Feed::Result??
    # what if not <rss> or <feed>? (ex. ben's is <rdf:RDF>, chokes parser)
    my $feed_uri = $self->{feedURL};
    $metadata = Bibliotech::CitationSource::blog::Feed->new($feed_uri, $blog_uri);

    die "Atom/RSS obj false\n"                   unless $metadata;
    die "Atom/RSS file contained zero entries\n" unless $metadata->{entry_count};
    die "URI in question not found in feed (may be old or unreachable, or URI is home page of blog): $feed_uri\n"
	                                         unless $metadata->{has_data};
  };

  if (my $e = $@) {
    if ($e =~ s/^warnstr: // or                # explicitly delivered
	$e =~ /file contained zero entries/ or # fairly common
	$e =~ /^URI in question not found/) {  # fairly common
      $self->warnstr($e);  # Level 1 error
      return undef;
    }

    die $e if $e =~ /at .* line \d+/;  # perl error, bubble up
    $self->errstr($e);                 # report the other errors
    return undef;
  }

  return undef unless defined $metadata;

  return Bibliotech::CitationSource::ResultList->new(Bibliotech::CitationSource::Result::Simple->new($metadata));
}

package Bibliotech::CitationSource::blog::Feed;
use base 'Class::Accessor::Fast';
use List::Util qw/first/;

__PACKAGE__->mk_accessors(qw/title author pubdate url has_data/);

# read URL
# parse with XML::Feed 
# XML::Feed will use XML::Atom::Feed or XML::RSS depending on which type of feed
sub new {
  my ($class, $feedURL, $origURL) = @_;

  my $self = bless {}, ref $class || $class;

  my $feed = eval { XML::Feed->parse(URI->new($feedURL)); };
  if (my $e = $@) {
    # Level 2 error: XML parsing error
    if ($e =~ /namespace error/) {
      my ($line) = $e =~ m/^\s?(:.*?):\d/gs;
      die "(truncated) $line\n";
    }

    # Level 1 error
    die "warnstr: $e\n" if $e =~ m/connect: timeout/ or
	                   $e =~ m/^:\d+: /m or
			   $e =~ m/not well-formed \(invalid token\)/;

    # disguise the error so it does not look like a perl error and will thus be emitted in errstr()
    $e =~ s/\bline (\d+)$/line:$1/;
    die "$e\n";
  }

  my $xe = XML::Feed->errstr;

  # Level 1 error (couldn't test this logic, might need to be tweaked)
  unless ($feed) {
    my $msg = (($xe || 'no feed')." ... regarding: $feedURL\n");
    die "warnstr: $msg\n";
  }
  
  $self->has_data(0);
  $self->parse($origURL, $feed) if $feed;
  return $self;
}

sub parse {
  my($self, $origURL, $feed) = @_;

  my @entries = $feed->entries;
  $self->{'entry_count'} = @entries;

  my $entry = first { $_->id eq $origURL || $_->link eq $origURL } @entries
      or return;  # not hit

  $self->{'has_data'}          = 1;
  $self->{'journal'}->{'name'} = $feed->title;
  $self->{'title'}             = $entry->title || $feed->title;
  $self->{'authors'}           = fix_authors($entry->author || $feed->author);
  $self->{'pubdate'}           = fix_date($entry->issued);
}

sub fix_authors {
  my $author_value = shift or return;

  # ex. Tim Bray
  my ($f, $l) = $author_value =~ /^(.*)\s+(.+)$/;
  return unless $f or $l;

  my $obj;
  $obj->{'forename'} = $f if $f;
  $obj->{'lastname'} = $l if $l;
  return [$obj];
}

sub fix_date {
  my $date_value = shift or return;
  return $date_value->ymd;
}

1;
__END__
