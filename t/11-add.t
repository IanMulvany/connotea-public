#!/usr/bin/perl

use Test::More tests => 44;
use Test::Exception;
use strict;
use warnings;

BEGIN {
  use_ok('Bibliotech::TestUtils') or exit;
  use_ok('Bibliotech') or exit;
};

is_table_empty_or_bail('Bibliotech::User');
is_table_empty_or_bail('Bibliotech::Bookmark');
is_table_empty_or_bail('Bibliotech::User_Bookmark');

my $bibliotech = get_test_bibliotech_object_1_test();
my $user       = get_test_user_7_tests($bibliotech);

$user->active(0);
$user->update;
throws_ok { $bibliotech->add(user => $user, uri => 'http://www.connotea.org/', tags => ['test']); }
          qr/inactive/, 'adding by inactive user caught ok';
$user->active(1);
$user->update;

foreach (qw(file:///my/hard/drive
            mailto:my@domain.com
            data:1234567890
            chrome://browser/path
            about://browser/path)) {
  my $uri    = URI->new($_);
  my $scheme = $uri->scheme;
  throws_ok { $bibliotech->add(user => $user, uri => $uri, tags => ['test']); }
            qr/$scheme:/, 'adding '.$scheme.': URI caught ok';
}

throws_ok { $bibliotech->add(user => $user, uri => 'test:'.('x' x 300), tags => ['test']); }
          qr/255 characters/, 'adding URI over 255 characters long caught';

throws_ok { $bibliotech->add(user => $user, uri => 'test:notags1'); }
          qr/one tag/, 'adding post with no tags caught';
Bibliotech::Bookmark->new('test:notags1')->delete;

throws_ok { $bibliotech->add(user => $user, uri => 'test:notags2', tags => []); }
          qr/one tag/, 'adding post with no tags caught (empty array)';
Bibliotech::Bookmark->new('test:notags2')->delete;

throws_ok { $bibliotech->add(user => $user, uri => 'test:invalidtag', tags => ['one+two']); }
          qr/invalid tag/i, 'adding post with invalid tag name caught';
Bibliotech::Bookmark->new('test:invalidtag')->delete;

my $user_bookmark;
lives_and {
  ok(defined($user_bookmark = $bibliotech->add(user => $user, uri => 'test:1', tags => ['test'],
					       skip_antispam => 1)),
     'user_bookmark defined');
} 'added test:1';
my $bookmark = Bibliotech::Bookmark->new('test:1');
$bookmark->delete if not defined $user_bookmark and defined $bookmark;
SKIP: {
  skip 'user_bookmark is not defined', 5 unless defined $user_bookmark;
  is($user_bookmark->private,           0, 'private 0');
  is($user_bookmark->private_gang,  undef, 'private_gang undef');
  is($user_bookmark->private_until, undef, 'private_until undef');
  is($user_bookmark->quarantined,   undef, 'quarantined undef');
  is($user_bookmark->def_public,        1, 'def_public 1');
}
$bookmark->delete if defined $bookmark;

lives_and {
  ok(defined($user_bookmark = $bibliotech->add(user => $user, uri => 'test:2', tags => ['test'],
					       private => 1,
					       skip_antispam => 1)),
     'user_bookmark defined');
} 'added test:2';
$bookmark = Bibliotech::Bookmark->new('test:2');
$bookmark->delete if not defined $user_bookmark and defined $bookmark;
SKIP: {
  skip 'user_bookmark is not defined', 5 unless defined $user_bookmark;
  is($user_bookmark->private,           1, 'private 1');
  is($user_bookmark->private_gang,  undef, 'private_gang undef');
  is($user_bookmark->private_until, undef, 'private_until undef');
  is($user_bookmark->quarantined,   undef, 'quarantined undef');
  is($user_bookmark->def_public,        0, 'def_public 0');
}
$bookmark->delete if defined $bookmark;

lives_and {
  ok(defined($user_bookmark = $bibliotech->add(user => $user, uri => 'test:3', tags => ['test'],
					       private_until => Bibliotech::Date->new('2200-01-01 01:00:00'),
					       skip_antispam => 1)),
     'user_bookmark defined');
} 'added test:3';
$bookmark = Bibliotech::Bookmark->new('test:3');
$bookmark->delete if not defined $user_bookmark and defined $bookmark;
SKIP: {
  skip 'user_bookmark is not defined', 5 unless defined $user_bookmark;
  is($user_bookmark->private,           0, 'private 0');
  is($user_bookmark->private_gang,  undef, 'private_gang undef');
  is($user_bookmark->private_until->mysql_datetime, '2200-01-01 01:00:00', 'private_until 2200-01-01 01:00:00');
  is($user_bookmark->quarantined,   undef, 'quarantined undef');
  is($user_bookmark->def_public,        0, 'def_public 0');
}
$bookmark->delete if defined $bookmark;

$user->delete;

is_table_empty('Bibliotech::User');
is_table_empty_or_bail('Bibliotech::Bookmark');
is_table_empty_or_bail('Bibliotech::User_Bookmark');
