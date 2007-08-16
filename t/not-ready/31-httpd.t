#!/usr/bin/perl

use strict;
use warnings;
#use Bibliotech;
#use Bibliotech::Apache;
use Apache::Test qw(:withtestmore);
use Test::More tests => 1;
use Apache::TestUtil;
use Apache::TestRequest qw(GET_BODY);

my $url = '/data/users';
my $data = GET_BODY $url;
  
is($data,
   "Amazing!",
   "basic test",
   );
