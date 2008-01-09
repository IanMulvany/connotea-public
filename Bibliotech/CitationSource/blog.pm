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
  '1.3';
}

sub understands {
  my ($self, $uri, $content_sub) = @_;

  return 0 unless $uri->scheme eq 'http';

  my ($ok, $response) = $self->catch_transient_warnstr
      (sub { my ($response) = $content_sub->();
	     $response->is_success or die $response->status_line."\n";
	     return $response;
       });
  $ok or return -1;

  my $content_type = $response->content_type;
  $content_type eq 'text/html' || $content_type eq 'application/xhtml+xml'
      or return 0;

  my $href = _get_feed_href_from_content($response->content)
      or return 0;
  $self->{feedURL} = URI->new_abs($href, $uri);

  return 3;  # 3 is the code for success from this module
}

# parse and load up the atom or rss <link> in the HTML file
sub _get_feed_href_from_content {
  my $content = shift or return;
  my @candidate_hrefs;
  my $parser = HTML::TokeParser->new(\$content);
  while (my $token = $parser->get_tag('link')) {
    my $href = $token->[1]->{href} or next;
    my $type = $token->[1]->{type} or next;
    my $rel  = $token->[1]->{rel}  || '';
    next unless $type =~ m,application/(rss|atom),i;
    return $href if lc($1) eq 'atom' and $rel eq 'alternate';  # use it if Atom
    push @candidate_hrefs, $href;                              # otherwise store as possibility
  }
  return $candidate_hrefs[0];  # use the first candiate if we got this far
}

sub citations {
  my ($self, $blog_uri, $content_sub) = @_;

  my $metadata;
  eval {
    $self->errstr('do not understand URI'), return undef unless $self->understands($blog_uri, $content_sub);
    my $feed_uri = $self->{feedURL} or die 'no feed link set';
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
			   $e =~ m/not well-formed \(invalid token\)/ or
			   $e =~ m/undefined entity at / or
			   $e =~ m/unclosed CDATA section at / or
			   $e =~ m/junk after document element at / or
			   $e =~ m/Couldn\'t open encmap /;

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
