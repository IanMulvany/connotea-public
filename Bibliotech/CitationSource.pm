# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource class provides a base class that is intended to be
# overridden by indivdual classes that provide citation details for specific
# types of URI's. Bibliotech::CitationSource::ResultList and various other classes
# are also defined below to set out the structure of return results.
#
# You can create your own citation module by creating a Perl module file under
# the Bibliotech/Citation/ directory. The first few lines of code should 
# probably look like this:
#     package Bibliotech::CitationSource::YourName;
#     use strict;
#     use base 'Bibliotech::CitationSource';
# ...and after that just override the methods below according to the comments.
# Look at Pubmed.pm, Amazon.pm, etc for examples of working citation modules.

package Bibliotech::CitationSource;
use strict;
use base 'Class::Accessor::Fast';
use Bibliotech::Config;
use Bibliotech::Util;
use Bibliotech::UserAgent;

# your module can optionally print debugging info if $Bibliotech::CitationSource::DEBUG is true
our $DEBUG = 0;

# use errstr to store errors when you are required by the API to return undef or zero, otherwise just die
# use warnstr to store warnings and notes that only appear in debugging tools
__PACKAGE__->mk_accessors(qw/bibliotech errstr warnstr/);

# you should have very little reason to override new() but you can as long as you run this one via SUPER::new()
# it is *not* recommended that you override new() without calling back to this one
sub new {
  my ($class, $bibliotech) = @_;
  my $self = Bibliotech::CitationSource->SUPER::new({bibliotech => $bibliotech});
  return bless $self, ref $class || $class;
}

# configuration key retrieval helper
sub cfg {
  Bibliotech::Config::Util::cfg(@_);
}

# same but required
sub cfg_required {
  Bibliotech::Config::Util::cfg_required(@_);
}

# should return 1 in an overridden module
sub api_version {
  0;  # zero will cause the module to be skipped
}

# should return a version number for the source module
# needs no correlation to the outside, just needs to be different each time the module is substantially changed
# if you set this to a CVS Revision keyword string in your source file to get a CVS revision number, only the numeric part will be used
sub version {
  'alpha-version';
}

# a human-readable name to refer to the citation module as a whole, e.g. 'Pubmed'
# if the module can read from multiple sources, use an inclusive name
sub name {
  undef;
}

# determine if this module can handle this URI
#
# input: URI object
#        coderef to get the document from the network - return values same as ua_act()
#
# return: -1 = mild/transient error (die for more serious error)
#          0 = do not understand URI
#          1 = definitely understand URI
#      2..10 = understand, but defer if another module understands with a score closer to 1
#              technically you can choose any winning score you like 1-10 but here's a rule of thumb:
#              1 = some direct treatment based on usually the hostname
#              2 = some treatment based on knowing the group of sites this belongs to
#              3 = some treatment based on common <link>'d file found on the page
#              4 = some treatment based on a microformat found in the page 
#              5 = some treatment based on scraping something from the page
# notes:
# - please check scheme is 'http' or something you can work with before calling other URI methods
# - if URI parameters are considered, some implementations may prefer to call understands_id() for validation
# - for optimization, if another module returns 1 before getting to yours, yours will not even be consulted
sub understands {
  0;
}

# accept a hashref of identifiers known to this module and return values the same as understands()
sub understands_id {
  0;
}

# the best score that understands() could return 1-10 (don't worry about -1 or 0)
sub potential_understands {
  1;
}

# optionally filter the URI
# accept a URI object and clean out any "bad" parts, e.g. user identifiers or login names
# THESE MUST BE BENIGN CHANGES THAT STILL POINT TO THE SAME FINAL DATA (IF THE USER IS AUTHORIZED)
# understands() will be called before this, whereas citations() will be called with the filtered URI
#
# input: URI object
#        coderef to get the document from the network - return values same as ua_act()
#
# return: object = replacement URI object (must be different than original - else return undef)
#             '' = abort, tell the user they cannot add this URI (set errstr to a nice user message if you like)
#          undef = no change
sub filter {
  undef;
}

# accept a URI object, fetch metadata, and return a Bibliotech::CitationSource::ResultList
#
# input: URI object
#        coderef to get the document from the network - return values same as ua_act()
#
# return: undef = no metadata available, or transient/network error (get sub will die, should be caught)
#        object = Bibliotech::CitationSource::ResultList (even if only one)
#
# note that many implementations may prefer to simply grab identifiers from the URI and call citations_id()
sub citations {
  undef;
}

# accept a hashref of identifiers known to this module and return values the same as citations()
sub citations_id {
  undef;
}

# all network requests should be via this get sub
# return value in scalar context: $charset_decoded_content_string
#                in list context: (HTTP::Response object, $charset_decoded_content_string, $extracted_html_title_if_html)
sub ua_act {
  my ($self, $uri_or_request, $ua) = @_;
  return Bibliotech::Util::get($uri_or_request,
			       defined $ua ? $ua : $self->bibliotech);
}

# acceptable alias
sub get {
  shift->ua_act(@_);
}

# where ua_act() is not completely sufficient, supply a way to get the UA
sub ua {
  return Bibliotech::Util::ua(shift->bibliotech);
}

# if your module realizes that it has obtained identifiers that can be used by citations_id() in a different
# module, you can call citations_id_switch() with the class name and a hashref that will then bootstrap the
# other module
sub citations_id_switch {
  my ($self, $class, $id_hashref) = @_;
  die "Please use Bibliotech::Plugin first.\n" unless $INC{'Bibliotech/Plugin.pm'};
  my $plugin = Bibliotech::Plugin->new;
  $class = 'Bibliotech::CitationSource::'.$class unless $class =~ /::/;
  my $other = $plugin->instance($class);
  return undef unless $other->understands_id($id_hashref);
  return $other->citations_id($id_hashref);
}

# perform an action (passed in as a code reference) and return a list: true, and then the value
# if an exception is thrown, return a one item list of zero
# the error will already be saved in errstr() for you
# use like this in your module:
#    my ($ok, $value) = $self->possible_transient_error(sub { ... });
#    $ok or return -1;
sub catch_transient_die {
  my ($self, $action_sub, $mutator) = @_;
  my $value = eval { return $action_sub->(); };
  return (1, $value) unless $@;
  die $@ if $@ =~ / at .* line /;  # go ahead and really die for a Perl error
  (my $e = $@) =~ s/\n$//;
  $mutator = 'errstr' unless $mutator && $mutator eq 'warnstr';
  $self->$mutator($e);
  return (0, $e);
}

sub catch_transient_errstr {
  catch_transient_die(@_, 'errstr');
}

sub catch_transient_warnstr {
  catch_transient_die(@_, 'warnstr');
}

sub content_or_set_warnstr {
  my ($self, $content_sub, $acceptable_content_types) = @_;
  die 'no content sub or is not code' unless defined $content_sub and ref($content_sub) eq 'CODE';
  my ($ok, $content) = $self->catch_transient_warnstr
      (sub { my ($response) = $content_sub->();
	     defined $response or die 'no response object';
	     $response->is_success or die $response->status_line."\n";
	     my $content_type = $response->content_type;
	     grep { $content_type =~ /$_/ } (@{$acceptable_content_types||[]})
		 or die "Content type is not acceptable ($content_type)\n";
	     return $response->content;
       });
  return $ok ? $content : undef;
}

package Bibliotech::CitationSource::ResultList;
use strict;
use base 'Set::Array';

# return next result or undef if finished
sub fetch {
  shift->shift;  # ;-)
}

package Bibliotech::CitationSource::Result;
use strict;

# a human-readable name to refer to what type of citation this is, e.g. 'Pubmed'
sub type {
  undef;
}

# a human-readable name of the source of this data, e.g. 'Pubmed database at eutils.ncbi.nlm.nih.gov'
sub source {
  undef;
}

# return a hashref of identification types and values, e.g. {'pubmed' => '111', 'doi' => '222'}
# return undef if no identifiers are known
sub identifiers {
  undef;
}

# return a requested identifier or undef, e.g. 'doi'
sub identifier {
  my ($self, $key) = @_;
  my $id_ref = $self->identifiers or return undef;
  return $id_ref->{lc($key)};
}

# return article title
# wide characters should be in Perl format - if you use Bibliotech::CitationSource::get() this is usually automatic
sub title {
  undef;
}

# return an object of author objects: Bibliotech::CitationSource::Result::AuthorList
sub authors {
  undef;
}

# return a journal object: Bibliotech::CitationSource::Result::Journal
sub journal {
  undef;
}

# return article volume identifier
sub volume {
  undef;
}

# return article issue identifier
sub issue {
  undef;
}

# return article issue page
sub page {
  undef;
}

# return date first published as YYYY-MM-DD
# where MM is digits or 3-letter English month abbreviation
# and MM and DD as digits do not need to be zero-padded
sub date {
  undef;
}

# return date record was created or last modified, same format as date()
# required - do not return undef
sub last_modified_date {
  undef;
}

package Bibliotech::CitationSource::Result::AuthorList;
use strict;
use base 'Set::Array';

sub fetch {
  shift->shift;  # ;-)
}

package Bibliotech::CitationSource::Result::Author;
use strict;

# return as many of these strings as possible (some duplicate each other):
sub firstname      { undef; }
sub forename       { undef; }
sub initials       { undef; }
sub middlename     { undef; }
sub lastname       { undef; }  # required
sub suffix         { undef; }
sub postal_address { undef; }
sub affiliation    { undef; }
sub email          { undef; }

package Bibliotech::CitationSource::Result::Journal;
use strict;

# return as many of these strings as possible:
sub name           { undef; }  # required
sub issn           { undef; }  # required
sub coden          { undef; }
sub country        { undef; }
sub medline_code   { undef; }
sub medline_ta     { undef; }
sub nlm_unique_id  { undef; }

1;
__END__
