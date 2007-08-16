#!/usr/bin/perl

use Test::More tests => 51;
use Test::Exception;
use strict;
use warnings;

BEGIN {
  use_ok('Bibliotech::Throttle') or exit;
};

*list = \&Bibliotech::Throttle::list_from_undef_scalar_or_arrayref;
is_deeply([list(undef)],             [],                'list_from_undef_scalar_or_arrayref(undef)');
is_deeply([list('hello')],           ['hello'],         'list_from_undef_scalar_or_arrayref(scalar)');
is_deeply([list(['hello','world'])], ['hello','world'], 'list_from_undef_scalar_or_arrayref(arrayref)');

*figure_delay = \&Bibliotech::Throttle::figure_delay;
is(figure_delay(10, 1, 0, 1, 10), 10, 'figure_delay no change');
is(figure_delay(11, 1, 0, 1, 10), 10, 'figure_delay max\'ed');
is(figure_delay( 0, 1, 0, 1, 10),  1, 'figure_delay min\'ed');
is(figure_delay( 1, 3, 1, 1, 10),  4, 'figure_delay multiplier/addition');

*_is_service_paused_early = \&Bibliotech::Throttle::_is_service_paused_early;
ok( _is_service_paused_early(1, 1, [], 		'1.2.3.4'), '_is_service_paused_early on');
ok(!_is_service_paused_early(0, 1, [], 		'1.2.3.4'), '_is_service_paused_early off');
ok(!_is_service_paused_early(1, 0, [], 		'1.2.3.4'), '_is_service_paused_early main off');
ok(!_is_service_paused_early(1, 1, ['1.2.3.4'], '1.2.3.4'), '_is_service_paused_early exempt');

*_is_service_paused = \&Bibliotech::Throttle::_is_service_paused;
ok( _is_service_paused(1, [], 	       '1.2.3.4'), '_is_service_paused on');
ok(!_is_service_paused(0, [], 	       '1.2.3.4'), '_is_service_paused off');
ok(!_is_service_paused(1, ['1.2.3.4'], '1.2.3.4'), '_is_service_paused exempt');

*_is_rapid_fire_by_last_hit = \&Bibliotech::Throttle::_is_rapid_fire_by_last_hit;
ok( _is_rapid_fire_by_last_hit(1000, 10, 1009), 	       '_is_rapid_fire_by_last_hit yes');
ok(!_is_rapid_fire_by_last_hit(1000, 10, 1011), 	       '_is_rapid_fire_by_last_hit no');

*is_rapid_fire_by_last_hit = \&Bibliotech::Throttle::is_rapid_fire_by_last_hit;
ok( is_rapid_fire_by_last_hit(10, 1009, sub { 1000 }, sub {}), 'is_rapid_fire_by_last_hit yes');
ok(!is_rapid_fire_by_last_hit(10, 1011, sub { 1000 }, sub {}), 'is_rapid_fire_by_last_hit no');

*tell_rapid_fire_by_last_hit_throttle = \&Bibliotech::Throttle::tell_rapid_fire_by_last_hit_throttle;
do {
  my %memcache;
  my $memcache_get = sub { my $key = shift; $memcache{$key}; };
  my $memcache_set = sub { my ($key, $value, $time) = @_; $memcache{$key} = $value; };

  ok(!(tell_rapid_fire_by_last_hit_throttle('test', 10, 1000, 'bot1', $memcache_get, $memcache_set))[0],
     'tell_rapid_fire_by_last_hit_throttle off');
  ok(!(tell_rapid_fire_by_last_hit_throttle('test', 10, 1010, 'bot1', $memcache_get, $memcache_set))[0],
     'tell_rapid_fire_by_last_hit_throttle off');
  ok( (tell_rapid_fire_by_last_hit_throttle('test', 10, 1011, 'bot1', $memcache_get, $memcache_set))[0],
     'tell_rapid_fire_by_last_hit_throttle on');
};

*_tell_rapid_fire_by_hit_stack_throttle = \&Bibliotech::Throttle::_tell_rapid_fire_by_hit_stack_throttle;
do {
  my %memcache;
  my $memcache_get = sub { my $key = shift; $memcache{$key}; };
  my $memcache_set = sub { my ($key, $value, $time) = @_; $memcache{$key} = $value; };

  ok(!(_tell_rapid_fire_by_hit_stack_throttle('test', 1, 5, 2, ['WWW::Connotea'], 1000, 'bot1', 'bot1', $memcache_get, $memcache_set))[0],
     '_tell_rapid_fire_by_hit_stack_throttle off');
  ok(!(_tell_rapid_fire_by_hit_stack_throttle('test', 1, 5, 2, ['WWW::Connotea'], 1001, 'bot1', 'bot1', $memcache_get, $memcache_set))[0],
     '_tell_rapid_fire_by_hit_stack_throttle off 1 second later');
  ok( (_tell_rapid_fire_by_hit_stack_throttle('test', 1, 5, 2, ['WWW::Connotea'], 1002, 'bot1', 'bot1', $memcache_get, $memcache_set))[0],
     '_tell_rapid_fire_by_hit_stack_throttle on 1 second later again');
};

*_tell_load_defer = \&Bibliotech::Throttle::_tell_load_defer;
ok(do { my $slept = 0;
	!(_tell_load_defer('test', 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			   6,  sub { 6 },  sub { 1 }, sub {}, sub { $slept = pop }))[0] and !$slept;
      }, '_tell_load_defer no');
ok(do { my $slept = 0;
	!(_tell_load_defer('test', 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			   11, sub { 10 }, sub { 1 }, sub {}, sub { $slept = pop }))[0] and $slept == 10;
      }, '_tell_load_defer no after sleeping');
ok(do { my $slept = 0;
	(_tell_load_defer('test', 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			  11, sub { 10 }, sub { 6 }, sub {}, sub { $slept = pop }))[0] and !$slept;
      }, '_tell_load_defer yes without being able to sleep');
ok(do { my $slept = 0;
	(_tell_load_defer('test', 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			  12, sub { 11 }, sub { 5 }, sub {}, sub { $slept = pop }))[0] and $slept == 10;
      }, '_tell_load_defer yes after sleeping');

*_tell_bot_throttle = \&Bibliotech::Throttle::_tell_bot_throttle;
do {
  my %memcache;
  my $memcache_get = sub { my $key = shift; $memcache{$key}; };
  my $memcache_set = sub { my ($key, $value, $time) = @_; $memcache{$key} = $value; };

  ok(!(_tell_bot_throttle(1, 30, 2, 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			  1000, '1.2.3.4', 'Firefox',
			  sub { 0 }, sub { 0 }, 1, sub { 1 }, sub { 1 }, sub {}, sub {},
			  $memcache_get, $memcache_set))[0],
     '_tell_bot_throttle no for human');
  ok(!(_tell_bot_throttle(1, 30, 2, 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			  1001, '1.2.3.4', 'Firefox',
			  sub { 0 }, sub { 0 }, 1, sub { 1 }, sub { 1 }, sub {}, sub {},
			  $memcache_get, $memcache_set))[0],
     '_tell_bot_throttle no for human 1 second later');
  ok(!(_tell_bot_throttle(1, 30, 2, 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			  1002, '1.2.3.4', 'Firefox',
			  sub { 0 }, sub { 0 }, 1, sub { 1 }, sub { 1 }, sub {}, sub {},
			  $memcache_get, $memcache_set))[0],
     '_tell_bot_throttle no for human 1 second later again');
  ok(!(_tell_bot_throttle(1, 30, 2, 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			  1100, '1.2.3.4', 'Firefox',
			  sub { 0 }, sub { 0 }, 20, sub { 20 }, sub { 1 }, sub {}, sub {},
			  $memcache_get, $memcache_set))[0],
     '_tell_bot_throttle no for human even with high load');
  ok(!(_tell_bot_throttle(1, 30, 2, 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			  1200, '1.2.3.4', 'Unknown Bot',
			  sub { 0 }, sub { 1 }, 1, sub { 1 }, sub { 1 }, sub {}, sub {},
			  $memcache_get, $memcache_set))[0],
     '_tell_bot_throttle no for assumed bot');
  ok(!(_tell_bot_throttle(1, 30, 2, 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			  1201, '1.2.3.4', 'Unknown Bot',
			  sub { 0 }, sub { 1 }, 1, sub { 1 }, sub { 1 }, sub {}, sub {},
			  $memcache_get, $memcache_set))[0],
     '_tell_bot_throttle no for assumed bot 1 second later');
  ok(!(_tell_bot_throttle(1, 30, 2, 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			  1202, '1.2.3.4', 'Unknown Bot',
			  sub { 0 }, sub { 1 }, 1, sub { 1 }, sub { 1 }, sub {}, sub {},
			  $memcache_get, $memcache_set))[0],
     '_tell_bot_throttle no for assumed bot 1 second later again');
  ok( (_tell_bot_throttle(1, 30, 2, 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			  1300, '1.2.3.4', 'Unknown Bot',
			  sub { 0 }, sub { 1 }, 20, sub { 20 }, sub { 1 }, sub {}, sub {},
			  $memcache_get, $memcache_set))[0],
     '_tell_bot_throttle yes for assumed bot with high load');
  ok(do { my $slept = 0;
	  !(_tell_bot_throttle(1, 30, 2, 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			       1400, '1.2.3.4', 'Unknown Bot',
			       sub { 0 }, sub { 1 }, 20, sub { 9 }, sub { 1 }, sub {}, sub { $slept = pop },
			       $memcache_get, $memcache_set))[0] and $slept == 10;
	},
     '_tell_bot_throttle no for assumed bot with high load after sleeping');
  ok(!(_tell_bot_throttle(1, 30, 2, 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			  1500, '1.2.3.4', 'Known Bot',
			  sub { 1 }, sub { 0 }, 1, sub { 1 }, sub { 1 }, sub {}, sub {},
			  $memcache_get, $memcache_set))[0],
     '_tell_bot_throttle no for known bot');
  ok( (_tell_bot_throttle(1, 30, 2, 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			  1501, '1.2.3.4', 'Known Bot',
			  sub { 1 }, sub { 0 }, 1, sub { 1 }, sub { 1 }, sub {}, sub {},
			  $memcache_get, $memcache_set))[0],
     '_tell_bot_throttle yes for known bot after 1 second');
  ok( (_tell_bot_throttle(1, 30, 2, 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			  1502, '1.2.3.4', 'Known Bot',
			  sub { 1 }, sub { 0 }, 1, sub { 1 }, sub { 1 }, sub {}, sub {},
			  $memcache_get, $memcache_set))[0],
     '_tell_bot_throttle yes for known bot after 1 second again');
  ok( (_tell_bot_throttle(1, 30, 2, 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			  1600, '1.2.3.4', 'Known Bot',
			  sub { 1 }, sub { 0 }, 20, sub { 20 }, sub { 1 }, sub {}, sub {},
			  $memcache_get, $memcache_set))[0],
     '_tell_bot_throttle yes for known bot with high load');
  ok(do { my $slept = 0;
	  !(_tell_bot_throttle(1, 30, 2, 10, 5, 1, 0, 1, 10, 1, 0, 1, 10,
			       1700, '1.2.3.4', 'Known Bot',
			       sub { 1 }, sub { 0 }, 20, sub { 9 }, sub { 1 }, sub {}, sub { $slept = pop },
			       $memcache_get, $memcache_set))[0] and $slept == 10;
	},
     '_tell_bot_throttle no for known bot with high load after sleeping');
};

*_is_user_agent_a_known_bot = \&Bibliotech::Throttle::_is_user_agent_a_known_bot;
ok(!_is_user_agent_a_known_bot('Firefox', ['Bot', 'Crawler'], 1),
   '_is_user_agent_a_known_bot(Firefox) no');
ok(_is_user_agent_a_known_bot('Bot',      ['Bot', 'Crawler'], 1),
   '_is_user_agent_a_known_bot(Bot) yes');
ok(_is_user_agent_a_known_bot(undef,      ['Bot', 'Crawler'], 1),
   '_is_user_agent_a_known_bot(undef) yes');
ok(!_is_user_agent_a_known_bot(undef,     ['Bot', 'Crawler'], 0),
   '_is_user_agent_a_known_bot(undef) no');

*_is_user_agent_an_assumed_bot = \&Bibliotech::Throttle::_is_user_agent_an_assumed_bot;
ok(!_is_user_agent_an_assumed_bot('Firefox', ['Firefox', 'Safari'], 1),
   '_is_user_agent_an_assumed_bot(Firefox) no');
ok(_is_user_agent_an_assumed_bot('Bot', ['Firefox', 'Safari'], 1),
   '_is_user_agent_an_assumed_bot(Bot) yes');
ok(_is_user_agent_an_assumed_bot(undef, ['Firefox', 'Safari'], 1),
   '_is_user_agent_an_assumed_bot(undef) yes');
ok(!_is_user_agent_an_assumed_bot(undef, ['Firefox', 'Safari'], 0),
   '_is_user_agent_an_assumed_bot(undef) no');
