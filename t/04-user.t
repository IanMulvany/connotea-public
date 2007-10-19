#!/usr/bin/perl

# Test script that creates a test user and verifies related interfaces
# are working correctly.

use Test::More tests => 18;
use Test::Exception;
use strict;
use warnings;

BEGIN {
  use_ok('Bibliotech::TestUtils') or exit;
}

my $username    = 'test_user';
my $password    = 'test_pass';
my $firstname   = 'test_first';
my $lastname    = 'test_last';
my $email       = 'digiphaze@digiphaze.com';

is_table_empty_or_bail('Bibliotech::User');

my $bibliotech = get_test_bibliotech_object_1_test();
my $user = get_test_user_7_tests($bibliotech,
  $username,
  $password,
  $firstname,
  $lastname,
  $email);

# forced failure tests

my $fail_user    = '2cool';
my $long_user    = 'Trust me, Trust yourself, anyone else.. Shoot em';
my $long_user2   = 'ThisIsAReallyLongNameTestForTheNewUserFunctionThatDoesNotHaveAnyUnusualCharsOrSpacesIShouldFail';
my $illegal_user = 'tag';
my $normal_user  = 'test_user2';
my $normal_email = 'root@digiphaze.com';

throws_ok { $bibliotech->new_user($fail_user,$password,$firstname,$lastname,$normal_email,undef,undef); } 
  qr/3-40 characters/i, 'disallow username starting with digit';
throws_ok { $bibliotech->new_user($long_user,$password,$firstname,$lastname,$normal_email,undef,undef); }
  qr/3-40 characters/i, 'disallow long username 1';
throws_ok { $bibliotech->new_user($long_user2,$password,$firstname,$lastname,$normal_email,undef,undef); }
  qr/3-40 characters/i, 'disallow long username 2';
throws_ok { $bibliotech->new_user($illegal_user,$password,$firstname,$lastname,$normal_email,undef,undef); }
  qr/3-40 characters/i, 'disallow illegal character in username';
throws_ok { $bibliotech->new_user($username,$password,$firstname,$lastname,$normal_email,undef,undef); }
  qr/is already taken/i, 'disallow duplicate username';
throws_ok { $bibliotech->new_user($normal_user,$password,$firstname,$lastname,$email,undef,undef); }
  qr/is already registered/i, 'disallow duplicate email address';

lives_ok { $user->delete; } 'delete user';

is_table_empty('Bibliotech::User');
