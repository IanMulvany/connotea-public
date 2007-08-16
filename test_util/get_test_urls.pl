#!/usr/bin/perl

use strict;
use warnings;

use Yahoo::Search;
use Getopt::Std;

my %options;

getopt('hdp', \%options);

usage(0) if $options{h};

my $search_string = '';

$search_string .= 'hostname:'.$options{d} if $options{d};
$search_string .= ' '.join(' ', map {'inurl:'.$_} split / /, $options{p}) if $options{p};

print usage() && exit(1) unless $search_string;

my @results = Yahoo::Search->Results(Doc => $search_string,
                                      AppId => "Connotea",
                                      Mode         => 'all', # all words
                                      Start        => 0,
                                      Count        => 100,
                                    
                                     );
 warn $@ if $@;

foreach (@results) {
    print $_->Url,"\n";
}



sub usage {

   print qq{Usage:
\$ perl get_test_urls -d 'domain' -p 'elements in the path'

};
   exit(shift);
}
