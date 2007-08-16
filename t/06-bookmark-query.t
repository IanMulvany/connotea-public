#!/usr/bin/perl

use Test::More tests => 95;
use Test::Exception;
use strict;
use warnings;
use Digest::MD5 qw/md5_hex/;
use DateTime;
use URI;

BEGIN {
  use_ok('Bibliotech::TestUtils') or exit;
  use_ok('Bibliotech::Command') or exit;
  use_ok('Bibliotech::Parser') or exit;
  use_ok('Bibliotech::Query') or exit;
  use_ok('Bibliotech::Util') or exit;
};

my @testdata =
    #  username    group            bookmarks
    (['bill',     'spacemen',     [['cnn.com'          => 'news', 'events'],
				   ['slashdot.org'     => 'news', 'geek', 'tech'],
				   ['space.com'        => 'space', 'tech'],
				   ['google.com'       => 'search', 'tech'],
				   ['SPACEMEN.COM'     => 'news', 'tech'],
				   ['PRIVATE.COM'      => 'news', 'tech'],
				   ],
      ],
     ['bob',      'weloveperl',   [['google.com'       => 'search engines'],
                                   ['thinkgeek.com'    => 'geek', 'toys'],
				   ],
      ],
     ['jim',      'spacemen',     [['slashdot.org'     => 'news'],
				   ['myspace.com'      => 'social networking', 'friends'],
				   ['msnbc.com'        => 'news', 'microsoft'],
				   ],
      ],
     ['joe',      'spacemen',     [['thefacebook.com'  => 'school', 'social networking'],
				   ['space.com'        => 'space news'],
				   ],
      ],
     ['tom',      'weloveperl',   [['vnboards.ign.com' => 'forums', 'gaming'],
				   ['neoreality.com'   => 'web design', 'programming'],
				   ['yahoo.com'        => 'community', 'web search'],
				   ['slashdot.org'     => 'news'],
				   ['anandtech.com'    => 'hardware', 'reviews'],
				   ],
      ],
     ['NEVERSHOW','NEVERSHOW',    [['NEVERSHOW.COM'    => 'NEVERSHOW']
				   ],
      ],
     );

map { my $user = Bibliotech::User->new($_); $user->delete if $user; 0; } map { $_->[0] } @testdata;

is_table_empty_or_bail('Bibliotech::User');
is_table_empty_or_bail('Bibliotech::Bookmark');
is_table_empty_or_bail('Bibliotech::User_Bookmark');

my $bibliotech = get_test_bibliotech_object_1_test();

populate_db(@testdata);

test(mc([user => ['bill','Bibliotech::User']]),
     'user_bookmarks', <<'', '/recent/user/bill');
bill -> cnn.com [events,news]
bill -> slashdot.org [tech,geek,news]
bill -> space.com [tech,space]
bill -> google.com [tech,search]

test(mc([user => ['bill','Bibliotech::User']]),
     'user_bookmarks', <<'', '/recent/user/bill as bill', undef, 'bill');
bill -> cnn.com [events,news]
bill -> slashdot.org [tech,geek,news]
bill -> space.com [tech,space]
bill -> google.com [tech,search]
bill -> SPACEMEN.COM [tech,news]
bill -> PRIVATE.COM [tech,news]

test(mc([user => ['bill','Bibliotech::User']],
	[start => 2]),
     'user_bookmarks', <<'', '/recent/user/bill?start=2', 4);
bill -> space.com [tech,space]
bill -> google.com [tech,search]

test(mc([user => ['bill','Bibliotech::User']],
	[num => 2]),
     'user_bookmarks', <<'', '/recent/user/bill?num=2', 4);
bill -> cnn.com [events,news]
bill -> slashdot.org [tech,geek,news]

test(mc([user => ['bill','Bibliotech::User']],
	[start => 1], [num => 2]),
     'user_bookmarks', <<'', '/recent/user/bill?start=1&num=2', 4);
bill -> slashdot.org [tech,geek,news]
bill -> space.com [tech,space]

test(mc([user => ['bill','Bibliotech::User']],
	[tag => ['tech','Bibliotech::Tag']]),
     'user_bookmarks', <<'', '/recent/user/bill/tag/tech');
bill -> slashdot.org [tech,geek,news]
bill -> space.com [tech,space]
bill -> google.com [tech,search]

test(mc([user => ['bill','Bibliotech::User']],
	[tag => ['tech','Bibliotech::Tag']]),
     'bookmarks', <<'', '/bookmarks/user/bill/tag/tech');
google.com
space.com
slashdot.org

test(mc([user => ['bill','Bibliotech::User']],
	[tag => [['news','Bibliotech::Tag'], ['tech','Bibliotech::Tag']]]),
     'user_bookmarks', <<'', '/recent/user/bill/tag/news+tech');
bill -> slashdot.org [tech,geek,news]

test(mc([user => ['bill','Bibliotech::User']],
	[tag => [['tech','Bibliotech::Tag'], ['news','Bibliotech::Tag']]]),
     'user_bookmarks', <<'', '/recent/user/bill/tag/tech+news (reverse order should not differ results)');
bill -> slashdot.org [tech,geek,news]

test(mc([user => ['bill','Bibliotech::User']],
	[tag => [['news','Bibliotech::Tag'], ['tech','Bibliotech::Tag']]]),
     'bookmarks', <<'', '/bookmarks/user/bill/tag/news+tech');
slashdot.org

test(mc([user => ['bill','Bibliotech::User']],
	[tag => [['tech','Bibliotech::Tag'], ['news','Bibliotech::Tag']]]),
     'bookmarks', <<'', '/bookmarks/user/bill/tag/tech+news');
slashdot.org

test(mc([user => ['bill','Bibliotech::User']],
	[tag => ['tech','Bibliotech::Tag'], ['news','Bibliotech::Tag']]),
     'user_bookmarks', <<'', '/recent/user/bill/tag/tech/news (each tag matches somewhere)');
bill -> cnn.com [events,news]
bill -> slashdot.org [tech,geek,news]
bill -> space.com [tech,space]
bill -> google.com [tech,search]

test(mc([user => ['bill','Bibliotech::User']]),
     'user_bookmarks', <<'', '/recent/user/bill as jim (should see group-private post)', undef, 'jim');
bill -> cnn.com [events,news]
bill -> slashdot.org [tech,geek,news]
bill -> space.com [tech,space]
bill -> google.com [tech,search]
bill -> SPACEMEN.COM [tech,news]

test(mc([user => ['bob','Bibliotech::User']],
	[tag => ['tech','Bibliotech::Tag'], ['news','Bibliotech::Tag']]),
     'user_bookmarks', <<'', '/recent/user/bob/tag/tech/news (no tags match)');

test(mc([user => ['jim','Bibliotech::User']],
	[tag => ['tech','Bibliotech::Tag'], ['news','Bibliotech::Tag']]),
     'user_bookmarks', <<'', '/recent/user/jim/tag/tech/news (one of two tags matches)');
jim -> slashdot.org [news]
jim -> msnbc.com [microsoft,news]

test(mc([user => ['bill','Bibliotech::User']],
	[tag => ['tech','Bibliotech::Tag'], ['news','Bibliotech::Tag']]),
     'bookmarks', <<'', '/bookmarks/user/bill/tag/tech/news (each tag matches somewhere)');
cnn.com
google.com
space.com
slashdot.org

SKIP: {
skip 'ambiguous specification - intersection of bookmarks or user_bookmarks', 1;
test(mc([user => ['bob','Bibliotech::User']],
	[tag => ['tech','Bibliotech::Tag'], ['news','Bibliotech::Tag']]),
     'bookmarks', <<'', '/bookmarks/user/bob/tag/tech/news (no tags match)');

};

test(mc([user => ['jim','Bibliotech::User']],
	[tag => ['tech','Bibliotech::Tag'], ['news','Bibliotech::Tag']]),
     'bookmarks', <<'', '/bookmarks/user/jim/tag/tech/news (one of two tags matches)');
msnbc.com
slashdot.org

test(mc([user => ['bill','Bibliotech::User'], ['jim','Bibliotech::User'], ['tom','Bibliotech::User']]),
     'user_bookmarks', <<'', '/recent/user/bill/jim/tom');
bill -> cnn.com [events,news]
bill -> slashdot.org [tech,geek,news]
bill -> space.com [tech,space]
bill -> google.com [tech,search]
jim -> slashdot.org [news]
jim -> myspace.com [friends,social networking]
jim -> msnbc.com [microsoft,news]
tom -> vnboards.ign.com [gaming,forums]
tom -> neoreality.com [programming,web design]
tom -> yahoo.com [web search,community]
tom -> slashdot.org [news]
tom -> anandtech.com [reviews,hardware]

test(mc([user => [['bill','Bibliotech::User'], ['jim','Bibliotech::User'], ['tom','Bibliotech::User']]]),
     'user_bookmarks', <<'', '/recent/user/bill+jim+tom');
bill -> slashdot.org [tech,geek,news]

test(mc([user => ['jim','Bibliotech::User']]),
     'gangs', <<'', '/groups/user/jim');
spacemen

test(mc([gang => ['spacemen','Bibliotech::Gang'], ['weloveperl','Bibliotech::Gang']]),
     'user_bookmarks', <<'', '/recent/group/spacemen/weloveperl');
bill -> cnn.com [events,news]
bill -> slashdot.org [tech,geek,news]
bill -> space.com [tech,space]
bill -> google.com [tech,search]
bob -> google.com [search engines]
bob -> thinkgeek.com [toys,geek]
jim -> slashdot.org [news]
jim -> myspace.com [friends,social networking]
jim -> msnbc.com [microsoft,news]
joe -> thefacebook.com [social networking,school]
joe -> space.com [space news]
tom -> vnboards.ign.com [gaming,forums]
tom -> neoreality.com [programming,web design]
tom -> yahoo.com [web search,community]
tom -> slashdot.org [news]
tom -> anandtech.com [reviews,hardware]

test(mc([gang => [['spacemen','Bibliotech::Gang'], ['weloveperl','Bibliotech::Gang']]]),
     'user_bookmarks', <<'', '/recent/group/spacemen+weloveperl');
bill -> slashdot.org [tech,geek,news]
bill -> google.com [tech,search]

test(mc([gang => ['spacemen','Bibliotech::Gang']],
	[tag => ['geek','Bibliotech::Tag']]),
     'user_bookmarks', <<'', '/recent/group/spacemen/tag/geek');
bill -> slashdot.org [tech,geek,news]

test(mc([tag => ['news','Bibliotech::Tag']]),
     'user_bookmarks', <<'', '/recent/tag/news');
bill -> cnn.com [events,news]
bill -> slashdot.org [tech,geek,news]
jim -> slashdot.org [news]
jim -> msnbc.com [microsoft,news]
tom -> slashdot.org [news]

test(mc([user => ['tom','Bibliotech::User']]),
     'tags', <<'', '/tags/user/tom');
forums
gaming
web design
programming
community
web search
news
hardware
reviews

test(mc([gang => ['spacemen','Bibliotech::Gang']]),
     'users', <<'', '/users/group/spacemen');
bill
jim
joe

test(mc([gang => ['weloveperl','Bibliotech::Gang']]),
     'tags', <<'', '/tags/gang/weloveperl');
search engines
geek
toys
forums
gaming
web design
programming
community
web search
news
hardware
reviews

test(mc([bookmark => ['slashdot.org','Bibliotech::Bookmark']]),
     'user_bookmarks', <<'', '/recent/uri/slashdot.org');
bill -> slashdot.org [tech,geek,news]
jim -> slashdot.org [news]
tom -> slashdot.org [news]

test(mc([bookmark => [md5_hex('slashdot.org'),'Bibliotech::Bookmark']]),
     'user_bookmarks', <<'', '/recent/uri/'.md5_hex('slashdot.org'));
bill -> slashdot.org [tech,geek,news]
jim -> slashdot.org [news]
tom -> slashdot.org [news]

test(mc([bookmark => ['slashdot.org','Bibliotech::Bookmark']]),
     'bookmarks', <<'', '/bookmarks/uri/slashdot.org');
slashdot.org

test(mc([bookmark => [md5_hex('slashdot.org'),'Bibliotech::Bookmark']]),
     'bookmarks', <<'', '/bookmarks/uri/'.md5_hex('slashdot.org'));
slashdot.org

test(mc([freematch => 'cnn']),
     'user_bookmarks', <<'', 'q=cnn (freematch only)');
bill -> cnn.com [events,news]

test(mc([freematch => 'cnn'], [num => 0]),
     'user_bookmarks', <<'', 'q=cnn&num=0 (num at zero)', 1);

test(mc([freematch => 'cnn'], [num => 2]),
     'user_bookmarks', <<'', 'q=cnn&num=2 (explicit num too high)');
bill -> cnn.com [events,news]

test(mc([freematch => 'news']),
     'user_bookmarks', <<'', 'q=news (freematch bookmark and tag)');
bill -> cnn.com [events,news]
jim -> msnbc.com [microsoft,news]
joe -> space.com [space news]
bill -> slashdot.org [tech,geek,news]

SKIP: {
skip 'freematch does not work for entities other than user_bookmarks', 1;
test(mc([freematch => 'cnn']),
     'bookmarks', <<'', '/bookmarks?q=cnn');
cnn.com

};

test(mc([date => ['2006-01-02','Bibliotech::Date']]),
     'user_bookmarks', <<'', '/recent/date/2006-01-02');
tom -> vnboards.ign.com [gaming,forums]
tom -> neoreality.com [programming,web design]
tom -> yahoo.com [web search,community]
tom -> slashdot.org [news]
tom -> anandtech.com [reviews,hardware]

test(mc([date => ['2006-01-02','Bibliotech::Date'], ['2006-01-04','Bibliotech::Date']]),
     'user_bookmarks', <<'', '/recent/date/2006-01-02/2006-01-04');
jim -> slashdot.org [news]
jim -> myspace.com [friends,social networking]
jim -> msnbc.com [microsoft,news]
tom -> vnboards.ign.com [gaming,forums]
tom -> neoreality.com [programming,web design]
tom -> yahoo.com [web search,community]
tom -> slashdot.org [news]
tom -> anandtech.com [reviews,hardware]

test(mc([date => [['2006-01-02','Bibliotech::Date'], ['2006-01-04','Bibliotech::Date']]]),
     'user_bookmarks', <<'', '/recent/date/2006-01-02+2006-01-04');
jim -> slashdot.org [news]

test(mc([date => ['2006-01-02','Bibliotech::Date']],
	[user => ['tom','Bibliotech::User']]),
     'user_bookmarks', <<'', '/recent/user/tom/date/2006-01-02');
tom -> vnboards.ign.com [gaming,forums]
tom -> neoreality.com [programming,web design]
tom -> yahoo.com [web search,community]
tom -> slashdot.org [news]
tom -> anandtech.com [reviews,hardware]

test(mc([date => ['2006-01-02','Bibliotech::Date']],
	[user => ['tom','Bibliotech::User']],
	[tag => ['hardware','Bibliotech::Tag']]),
     'user_bookmarks', <<'', '/recent/user/tom/tag/hardware/date/2006-01-02');
tom -> anandtech.com [reviews,hardware]

test(mc([date => ['2006-01-02','Bibliotech::Date']],
	[user => ['tom','Bibliotech::User']],
	[tag => ['hardware','Bibliotech::Tag']],
	[bookmark => [md5_hex('anandtech.com'),'Bibliotech::Bookmark']]),
     'user_bookmarks', <<'', '/recent/user/tom/tag/hardware/date/2006-01-02/uri/'.md5_hex('anandtech.com'));
tom -> anandtech.com [reviews,hardware]

test(mc([date => ['2006-01-02','Bibliotech::Date']],
	[tag => ['hardware','Bibliotech::Tag']]),
     'user_bookmarks', <<'', '/recent/tag/hardware/date/2006-01-02');
tom -> anandtech.com [reviews,hardware]

unwind_db(@testdata);

sub unwind_db {
  # cascade delete everything we created
  map { Bibliotech::User->new($_)->delete } map { $_->[0] } @_;
}

sub populate_db {

  # infrastructure to be able to create rows with incrementing
  # timestamps on proper days that tick over starting the day after
  # the initial value for $faketime:
  my $faketime = Bibliotech::Date->new('2005-12-31 00:00:00');
  my $counter;
  my $nextday  = sub { $faketime->add(days => 1);
		       DateTime::set($faketime, hour => 9, minute => 0, second => 0);
		       $counter = $faketime->epoch;
		     };
  my $nexttime = sub { Bibliotech::Date->from_epoch(epoch => $counter++); };
  my $find_or_create_with_custom_created_timestamp = sub {
    my ($class, $find_hashref, $created) = @_;
    my ($obj) = $class->search(%{$find_hashref});
    return $obj if defined $obj;
    $obj = $class->create($find_hashref);
    $obj->created($created);
    $obj->update;
    return $obj;
  };
  my $NEXT = sub { $find_or_create_with_custom_created_timestamp->(@_, $nexttime->()) };

  foreach (reverse @_) {
    $nextday->();
    my ($username, $gangname, $posts_arrayref) = @{$_};
    my $user = $NEXT->('Bibliotech::User', {username => $username});
    my $gang = $NEXT->('Bibliotech::Gang', {name => $gangname});
    $NEXT->('Bibliotech::User_Gang', {user => $user, gang => $gang});
    foreach (reverse @{$posts_arrayref}) {
      my $uri = shift @{$_};
      my $bookmark = $NEXT->('Bibliotech::Bookmark', {url => URI->new($uri)});
      my $user_bookmark = $NEXT->('Bibliotech::User_Bookmark', {user => $user, bookmark => $bookmark});
      foreach (reverse @{$_}) {
	my $tag = $NEXT->('Bibliotech::Tag', {name => $_});
	$NEXT->('Bibliotech::User_Bookmark_Tag', {user_bookmark => $user_bookmark, tag => $tag});
      }
      if ($uri =~ /private/i) {
	$user_bookmark->private(1);
	$user_bookmark->def_public(0);
	$user_bookmark->update;
      }
      elsif ($uri =~ /\Q$gangname\E/i) {
	$user_bookmark->private_gang($gang);
	$user_bookmark->def_public(0);
	$user_bookmark->update;
      }
    }
  }
}

# mc = "make command object"
# using this negates a dependency on Bibliotech::Parser
sub mc {
  Bibliotech::Command->new({map {
    my $key = shift @{$_};
    my $value = eval {
      return shift @{$_} if $key eq 'start' or $key eq 'num';
      return Bibliotech::Parser::Freematch->new(@{$_}) if $key eq 'freematch';
      return Bibliotech::Parser::NamePartSet->new(map {
	ref $_->[0] eq 'ARRAY'
	    ? [map { Bibliotech::Parser::NamePart->new(@{$_}) } @{$_}]
	    : Bibliotech::Parser::NamePart->new(@{$_})
	  } @{$_});
    };
    die $@ if $@;
    $key => $value;
  } @_ });
}

sub test {
  my ($command, $output_method, $expected_output, $test_name, $expected_count, $run_as_user) = @_;
  my $query = Bibliotech::Query->new($command, $bibliotech);
  $query->activeuser(Bibliotech::User->new($run_as_user)) if defined $run_as_user;
  is(join('', map { $_->plain_content."\n" } $query->$output_method), $expected_output, $test_name);
  $expected_count ||= do { my @lines = split(/\n/, $expected_output); scalar @lines; };
  is($query->lastcount, $expected_count, $test_name.' count='.$expected_count);
}
