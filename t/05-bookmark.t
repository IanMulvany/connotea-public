#!/usr/bin/perl

# Bookmark creation testing

use Test::More tests => 52;
use Test::Exception;
use strict;
use warnings;
use Data::Dumper;

BEGIN {
    use_ok('Bibliotech::TestUtils') or exit;
}

# Setup a test user to attach bookmarks to.

my $username    = 'test_user';
my $password    = 'test_pass';
my $firstname   = 'test_first';
my $lastname    = 'test_last';
my $email       = 'digiphaze@digiphaze.com';
my $booktest    = 'http://www.slashdot.org/';
my $booktitle   = 'Slashdot';
my $valid_date  = '2010-04-04 10:10:10';
my $part_date   = '2011-02';
my $past_date   = '2002-10-10 00:00:00';
my $inv_date    = 'this can not be a date';
my @valid_tag   = ('test_space', 'test_geology', 'test_aerospace');
my $fail_tag    = '/\\';

is_table_empty_or_bail('Bibliotech::User');
is_table_empty_or_bail('Bibliotech::Bookmark');
is_table_empty_or_bail('Bibliotech::Article');
is_table_empty_or_bail('Bibliotech::User_Article');

my $bibliotech = get_test_bibliotech_object_1_test();

my $user = get_test_user_7_tests($bibliotech,
    $username,
    $password,
    $firstname,
    $lastname,
    $email
);

my $bookmark = get_test_bookmark_7_tests(
    $bibliotech,
    $booktest,
    $booktitle,
);

# Force fail preadd with no arguments.
throws_ok { 
    $bibliotech->preadd
} qr/must specify/i, 'preadd fails with undefined uri';

# Force fail preadd with an invalid URL.
throws_ok {
    $bibliotech->preadd(uri => 'file:///tmp/stuff')
} qr/not allowed/i, 'preadd fails with file:// uri';

# Give Bibliotech::Date a partial future date and verify we recieve a
# Bibliotech::Date::Incomplete object, yet retain its validity.
my $private_until;
lives_ok {
    $private_until = new Bibliotech::Date($part_date,1);
} 'Bibliotech::Date::Incomplete';
isa_ok ($private_until, 'Bibliotech::Date::Incomplete');
ok (!$private_until->invalid, 'Date is not invalid');
ok (!$private_until->has_been_reached, 'Date has not been reached');

# Give Bibliotech::Date a completely invalid date and make sure we get the
# Bibliotech::Date::Incomplete object with the invalid flag set.
lives_ok {
    $private_until = new Bibliotech::Date($inv_date,1);
} 'Bibliotech::Date::Incomplete Invalid';
isa_ok ($private_until, 'Bibliotech::Date::Incomplete');
is ($private_until->invalid,1,'Date is invalid.');

# Give Bibliotech::Date a valid past address and verify return object is
# Bibliotech::Date with invalid flag NOT set and has_been_reached flag set.
lives_ok {
    $private_until = new Bibliotech::Date($past_date,1);
} 'Bibliotech::Date old';
isa_ok ($private_until, 'Bibliotech::Date');
ok (!$private_until->invalid, 'Past date but valid');
is ($private_until->has_been_reached,1, 'Valid date but in past');

# Check Bibliotech::Date functionality with a valid and future date.
lives_ok {
    $private_until = new Bibliotech::Date($valid_date,1);
} 'Bibliotech::Date';
isa_ok ($private_until, 'Bibliotech::Date');
ok (!$private_until->invalid, 'Date is not invalid');
ok (!$private_until->has_been_reached, 'Date has not been reached');

# Verify check_tag_format functionality for both pass and fail.
#my $parser = $bibliotech->parser;
#is ($parser->check_tag_format($valid_tag[0]),1,'check_tag_format');
#is ($parser->check_tag_format($fail_tag),0,'check_tag_format fail');

#Bibliotech::SpecialTagSet->scan(\$@valid_tag);

# Link the test user to the bookmark.
my $user_article;
lives_ok {
    $user_article = $user->link_bookmark($bookmark);
} 'link_bookmark';

# Check that link_bookmark returns a User_Article object and verify that the
# created entry id is is a positive number.
isa_ok($user_article,'Bibliotech::User_Article');
ok ($user_article->user_article_id ge 0, 'user_article_id integrity');

# Using the previous valid private_until date, apply it to bookmark and verify
# application.
ok ($user_article->private_until($private_until), 'Set private_until date');
isa_ok($user_article->private_until, 'Bibliotech::Date');
is ($user_article->private_until->utc_year,$private_until->utc_year,
    'private_until matches test value');

$user_article->update;

# Set the test user as the first user of the bookmark.
# Verify that readback is the test user.
ok ($bookmark->first_user($user), 'set first user');
is ($bookmark->first_user->username,$username,'first_user verify');

$bookmark->update;

# Now that bookmark is linked, make sure count_active is returning the correct
# number of users from the user bookmark table.
is (Bibliotech::User->count_active,1,'user bookmark setup verify');

lives_ok { $user_article->delete } 'delete user_article';
is_table_empty('Bibliotech::User_Article');
is_table_empty('Bibliotech::Article');
is_table_empty('Bibliotech::Bookmark');

lives_ok { $user->delete } 'delete user';
is_table_empty('Bibliotech::User');
