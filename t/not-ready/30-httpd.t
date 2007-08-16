#!/usr/bin/perl

# Test script to test page readback via a test httpd process
# listening on a test port.

use LWP::Simple;
use strict;
use warnings;

use Test::More tests => 0;
use Test::Exception;

my $apache = $ARGV[0];
my $config_file = $ARGV[1];

my $pid = fork();
if (not defined $pid) {
  print "Resources unavailable for fork.\n";
}
elsif ($pid == 0) {
  tests => 1;
  print "Child thread sleeping for 8s.\n";
  #sleep 8; # Wait for parent thread to load Apache
  print "Child starting test runs.\n";

  my $returned_data;
  
  $returned_data = get('http://bibliotech.digiphaze.com');
  
is($returned_data, <<'EOO', 'Homepage test');
this is a test
EOO

  exit(0);
}
else {
  print "Paren thread reporting for duty.\n";
  
  #my $apache_output = `$apache -x -f $config_file`;
}
