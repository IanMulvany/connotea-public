# Copyright 2006 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Plugin class provides a base class that is intended to be
# overridden by indivdual classes that provide proxy translation for specific
# types of URI's.
#
# You can create your own citation module by creating a Perl module file under
# the Bibliotech/Proxy/ directory. The first few lines of code should 
# probably look like this:
#     package Bibliotech::Proxy::YourName;
#     use strict;
#     use base 'Bibliotech::Proxy';
# ...and after that just override the methods below according to the comments.

package Bibliotech::Proxy;
use strict;
use base 'Class::Accessor::Fast';

# your module can optionally print debugging info if $Bibliotech::Proxy::DEBUG is true
our $DEBUG = 0;

# use errstr to store errors when you are required by the API to return undef or zero, otherwise just die
# use warnstr to store warnings and notes that only appear in debugging tools
__PACKAGE__->mk_accessors(qw/bibliotech errstr warnstr/);

# you should have very little reason to override new() but you can as long as you run this one via SUPER::new()
# it is *not* recommended that you override new() without calling back to this one
sub new {
  my ($class, $bibliotech) = @_;
  my $self = Bibliotech::Plugin->SUPER::new({bibliotech => $bibliotech});
  return bless $self, ref $class || $class;
}

# configuration key retrieval helper
sub cfg {
  Bibliotech::Util::cfg(@_);
}

# same but required
sub cfg_required {
  Bibliotech::Util::cfg_required(@_);
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

# filter the URI
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

1;
__END__
