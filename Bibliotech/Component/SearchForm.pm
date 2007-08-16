# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::Search class provides a search form.

package Bibliotech::Component::SearchForm;
use strict;
# base was Bibliotech::Component, but /rss/search?q=xxx didn't
# work because this is the main component for
# Bibliotech::Page::Search yet it has no rss_content().
# We use ListOfRecent explicitly in a search.tpl and then
# this base to underlay the other *_content() routines.
# We also had to remove last_updated_basis() because its not
# fine-grained enough to return a different value for HTML
# content vs other content.
use base 'Bibliotech::Component::ListOfRecent';
use URI;
use URI::QueryParam;
use Digest::MD5 qw/md5_hex/;
use Bibliotech::Command;

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $bibliotech = $self->bibliotech;
  my $location   = $bibliotech->location;
  my $command    = $bibliotech->command;
  my $page       = $command->page;
  my $cgi        = $bibliotech->cgi;
  my $canonical  = sub { $command->canonical_uri($location, {page => [set => 'recent'], output => [set => 'html'], @_}) };
  my $validationmsg;

  if ($cgi->param('form')) {
    my $uri;
    eval {
      my $phrase     = $cgi->param('q');
      my $type       = $cgi->param('type') || 'all';
      my $submit_uri = $cgi->param('uri');
      if ($type eq 'current') {
	$uri = URI->new($submit_uri);
	$uri->query_param('q' => $phrase);
	$uri->query_param_delete('start');
      }
      elsif ($type eq 'all') {
	$uri = URI->new($location.'search');
	$uri->query_param('q' => $phrase);
      }
      elsif ($type eq 'library') {
	$uri = URI->new($location.'library');
	$uri->query_param('q' => $phrase);
      }
      elsif ($type eq 'tag' or $type eq 'user') {
	$phrase =~ s|\s*\+\s*|+|g;
	# this next bit is designed for tags, but we let it be for users as well
	my @tags = $bibliotech->parser->tag_search($phrase) or
	    die "Missing ${type}s, malformed ${type}s, or use of a reserved keyword as a ${type}.\n";
	my $tags = join('/', map { ref $_ ? join('+', @{$_}) : $_; } @tags);
	$uri = $canonical->($type => [set => $tags]);
      }
      elsif ($type eq 'uri') {
	$uri = $canonical->(bookmark => [set => md5_hex($phrase)]);
      }
      elsif ($type eq 'google') {
	$uri = URI->new('http://www.google.com/search');
	(my $domain = $location->host) =~ s/^www\.//;
	$uri->query_param('q' => "site:$domain $phrase");
      }
      else {
	die "Invalid search type: $type\n";
      }
    };
    if ($@) {
      $validationmsg = $@;
    }
    else {
      die "Location: $uri\n";
    }
  }

  if ($main) {

    # error ... just show it
    return Bibliotech::Page::HTML_Content->simple($cgi->div({class => 'errormsg'}, $validationmsg))
	if $validationmsg;

    # have been called with a phrase in the main area - drop to ListOfRecent to show results
    return $self->SUPER::html_content($class, $verbose, $main)
	if $cgi->param('q');

    # no error, no search, just a hit on /search probably ... just display a short message
    return Bibliotech::Page::HTML_Content->simple($cgi->p('Please search above.'));

  }

  return Bibliotech::Page::HTML_Content->simple
      ($self->tt('compsearch',
		 do {
		   my $in_query      = defined $bibliotech->query && $bibliotech->command->filters_used;
		   my $in_my_library = $bibliotech->in_my_library;
		   {show_option_current => $in_query,
		    default_option      => eval { return 'library' if $in_my_library;
						  return 'current' if $in_query;
						  return 'all';
						},
		  },
		}));
}

1;
__END__
