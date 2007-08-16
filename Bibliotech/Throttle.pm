# Copyright 2006 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Throttle class contains helper routines for
# Bibliotech::Apache.

package Bibliotech::Throttle;
use strict;
use List::Util qw/min max sum first/;
use List::MoreUtils qw/any none/;
use Bibliotech::Cache;
use Bibliotech::Config;
use Bibliotech::Util;

# _is...     - purely functional routines, same output for same input, no side effects
# is...      - side effects ok if done by calling in passed in code refs, look up global vars ok
# do...      - perform all side effects necessary
# _tell...   - same as _is... but returns side effects code ref that acts on ($r,$log) as well as true/false
# tell...    - same as is... but returns side effects code ref that acts on ($r,$log) as well as true/false

our $SERVICE_PAUSED   		  = Bibliotech::Config->get('SERVICE_PAUSED');
our $SERVICE_PAUSED_EARLY         = Bibliotech::Config->get('SERVICE_PAUSED_EARLY');
our $SERVICE_NEVER_PAUSED_FOR     = Bibliotech::Config->get('SERVICE_NEVER_PAUSED_FOR');
our $LOAD_DEFER_MUL 		  = Bibliotech::Config->get('LOAD_DEFER_MUL') || 1;
our $LOAD_DEFER_ADJ 		  = Bibliotech::Config->get('LOAD_DEFER_ADJ') || 0;
our $LOAD_DEFER_MIN 		  = Bibliotech::Config->get('LOAD_DEFER_MIN') || 0;
our $LOAD_DEFER_MAX 		  = Bibliotech::Config->get('LOAD_DEFER_MAX') || 30;
our $LOAD_WAIT_MUL  		  = Bibliotech::Config->get('LOAD_WAIT_MUL') || 1;
our $LOAD_WAIT_ADJ  		  = Bibliotech::Config->get('LOAD_WAIT_ADJ') || 0;
our $LOAD_WAIT_MIN  		  = Bibliotech::Config->get('LOAD_WAIT_MIN') || 0;
our $LOAD_WAIT_MAX  		  = Bibliotech::Config->get('LOAD_WAIT_MAX') || 30;
our $BOT_THROTTLE       	  = Bibliotech::Config->get('BOT_THROTTLE');
our $ANTI_THROTTLE_FOR            = Bibliotech::Config->get('ANTI_THROTTLE_FOR') ||
                                      ['^Mozilla/[\d\.]+ .*(Gecko|KHTML|MSIE)',
				       '^Opera/[\d\.]+\b',
				       '^amaya/[\d\.]+\b',
				       '^Democracy/[\d\.]+\b',
				       '^Dillo/[\d\.]+\b',
				       '^iCab/[\d\.]+\b',
				       '^IBrowse/[\d\.]+\b',
				       '^ICE Browser/[\d\.]+\b',
				       '^(Lynx/[\d\.]+|Links)\b',
				       'NetPositive',
				       '^Emacs-',
				       'WWW::Connotea',
				       ];
our $THROTTLE_FOR  		  = Bibliotech::Config->get('THROTTLE_FOR') || [];
our $LOAD_MAX                     = Bibliotech::Config->get('LOAD_MAX') || 25;
our $DYNAMIC_THROTTLE      	  = Bibliotech::Config->get('DYNAMIC_THROTTLE');
our $DYNAMIC_THROTTLE_TIME 	  = Bibliotech::Config->get('DYNAMIC_THROTTLE_TIME') || 15;
our $DYNAMIC_THROTTLE_HITS 	  = Bibliotech::Config->get('DYNAMIC_THROTTLE_HITS') || 10;
our $DYNAMIC_THROTTLE_NEVER_FOR   = Bibliotech::Config->get('DYNAMIC_THROTTLE_NEVER_FOR') || [ 'WWW::Connotea' ];
our $BOT_LONE_THROTTLE_TIME       = Bibliotech::Config->get('BOT_LONE_THROTTLE_TIME') || 30;
our $BOT_ALL_THROTTLE_TIME        = Bibliotech::Config->get('BOT_ALL_THROTTLE_TIME') || 2;
our $SLEEPING_MAX                 = Bibliotech::Config->get('SLEEPING_MAX') || 10;

sub HTTP_SERVICE_UNAVAILABLE {
  503;
}

sub list_from_undef_scalar_or_arrayref {
  local $_ = shift;
  return () unless defined $_;
  return ($_) unless ref $_;
  return @{$_};
}

# calculate a number of seconds to delay based on four provided values that come from the configuration
sub figure_delay {
  my ($value, $multiplier, $adjustment, $minimum, $maximum) = @_;
  return max(min($value * $multiplier + $adjustment, $maximum), $minimum);
}

sub _is_service_paused_early {
  my ($config_early_switch, $config_switch, $config_exemption_list, $remote_ip) = @_;
  return unless $config_early_switch;
  return _is_service_paused($config_switch, $config_exemption_list, $remote_ip);
}

sub is_service_paused_early {
  my $remote_ip = shift;
  return _is_service_paused_early($SERVICE_PAUSED_EARLY, $SERVICE_PAUSED, $SERVICE_NEVER_PAUSED_FOR, $remote_ip);
}

sub _is_service_paused {
  my ($config_switch, $config_exemption_list, $remote_ip) = @_;
  return unless $config_switch;
  my @exempt = list_from_undef_scalar_or_arrayref($config_exemption_list) or return 1;
  return none { $remote_ip eq $_ } @exempt;
}

sub is_service_paused {
  my $remote_ip = shift;
  return _is_service_paused($SERVICE_PAUSED, $SERVICE_NEVER_PAUSED_FOR, $remote_ip);
}

sub do_service_paused_early {
  is_service_paused_early(shift->request->connection->remote_ip);
}

sub do_service_paused {
  is_service_paused(shift->request->connection->remote_ip);
}

sub is_service_paused_at_all {
  return $SERVICE_PAUSED;
}

sub _is_rapid_fire_by_last_hit {
  my ($last_hit_timestamp, $wait_time, $now) = @_;
  return $last_hit_timestamp > $now - $wait_time;
}

sub is_rapid_fire_by_last_hit {
  my ($wait_time, $now, $last_hit_timestamp_get, $last_hit_timestamp_set) = @_;
  return 1 if _is_rapid_fire_by_last_hit($last_hit_timestamp_get->(), $wait_time, $now);
  $last_hit_timestamp_set->($now);
  return;
}

sub tell_rapid_fire_by_last_hit_throttle {
  my ($logname, $wait_time, $now, $who, $memcache_get, $memcache_set) = @_;
  my $bot_cache_key = Bibliotech::Cache::Key->new(class => __PACKAGE__,
						  method => 'do_generic_throttle',
						  id => 'bot',
						  id => $who);
  if (is_rapid_fire_by_last_hit($wait_time, $now,
				sub { $memcache_get->($bot_cache_key) || 0 },
				sub { $memcache_set->($bot_cache_key, @_) }
				)) {
    return (1, sub { my ($r, $log) = @_;
		     $r->err_headers_out->set('Retry-After' => $wait_time);
		     $log->info("$logname is holding back a bot due to rapid fire: $who");
		     return HTTP_SERVICE_UNAVAILABLE;
		   });
  }
  return (0, sub { my ($r, $log) = @_;
		   $log->info("$logname is allowing a bot: $who");
		   return;
		 });
}

sub _tell_load_defer {
  my ($logname,
      $config_load_max, $config_sleeping_max,
      $config_load_defer_mul, $config_load_defer_adj, $config_load_defer_min, $config_load_defer_max,
      $config_load_wait_mul,  $config_load_wait_adj,  $config_load_wait_min,  $config_load_wait_max,
      $current_load, $load_get,
      $sleeping_incr, $sleeping_decr, $go_to_sleep_sub) = @_;
  return (0, undef) if !$config_load_max or $current_load <= $config_load_max;
  my $sleeping = $sleeping_incr->();
  my $already_sleeping = $sleeping - 1;
  my ($yes, $act) = eval {
    return (1, sub {
      my ($r, $log) = @_;
      $log->info("$logname is holding back a request due to high load ($current_load) - could not sleep because $already_sleeping processes are sleeping");
    }) if $sleeping > $config_sleeping_max;
    $go_to_sleep_sub->($logname,
		       figure_delay($current_load,
				    $config_load_defer_mul, $config_load_defer_adj,
				    $config_load_defer_min, $config_load_defer_max));
    my $new_load = $load_get->();
    return (0, sub {
      my ($r, $log) = @_;
      $log->info("$logname allowed a request after sleeping ($current_load, $new_load)");
    }) if $new_load <= $config_load_max;
    return (1, sub {
      my ($r, $log) = @_;
      my $wait = figure_delay($new_load,
			      $config_load_wait_mul, $config_load_wait_adj,
			      $config_load_wait_min, $config_load_wait_max);
      $r->err_headers_out->set('Retry-After' => $wait);
      $r->err_headers_out->set('Refresh' => "$wait; URL=".($r->uri.($r->args ? '?'.$r->args : '')))
	  if $r->method eq 'GET';
      $log->info("$logname is holding back a request due to high load ($current_load, $new_load)");
      return HTTP_SERVICE_UNAVAILABLE;
    });
  };
  die $@ if $@;
  $sleeping_decr->();
  return ($yes, $act);
}

sub tell_load_defer {
  my ($logname, $current_load, $load_get, $sleeping_incr, $sleeping_decr, $go_to_sleep_sub) = @_;
  return _tell_load_defer($logname,
			  $LOAD_MAX, $SLEEPING_MAX,
			  $LOAD_DEFER_MUL, $LOAD_DEFER_ADJ, $LOAD_DEFER_MIN, $LOAD_DEFER_MAX,
			  $LOAD_WAIT_MUL,  $LOAD_WAIT_ADJ,  $LOAD_WAIT_MIN,  $LOAD_WAIT_MAX,
			  $current_load, $load_get,
			  $sleeping_incr, $sleeping_decr, $go_to_sleep_sub);
}

sub _tell_bot_throttle {
  my ($switch,
      $config_bot_lone_time, $config_bot_all_time,
      $config_load_max, $config_sleeping_max,
      $config_load_defer_mul, $config_load_defer_adj, $config_load_defer_min, $config_load_defer_max,
      $config_load_wait_mul,  $config_load_wait_adj,  $config_load_wait_min,  $config_load_wait_max,
      $now, $remote_ip, $user_agent,
      $is_known_bot_sub, $is_assumed_bot_sub,
      $current_load, $load_get,
      $sleeping_incr, $sleeping_decr, $go_to_sleep_sub,
      $memcache_get, $memcache_set) = @_;
  return unless $switch;
  if (my $match = $is_known_bot_sub->($user_agent)) {
    my @act;
    my $all_act = sub { my ($r, $log) = @_; map { $_->($r, $log) } @act };
    do {
      my ($yes, $act) = tell_rapid_fire_by_last_hit_throttle
	  ('throttle[known,lone]', $config_bot_lone_time, $now, join(':', $remote_ip, $match),
	   $memcache_get, $memcache_set);
      push @act, $act if defined $act;
      return (1, $all_act) if $yes;
    };
    do {
      my ($yes, $act) = tell_rapid_fire_by_last_hit_throttle
	  ('throttle[known,all]', $config_bot_all_time, $now, 'all',
	   $memcache_get, $memcache_set);
      push @act, $act if defined $act;
      return (1, $all_act) if $yes;
    };
    do {
      my ($yes, $act) = _tell_load_defer
	  ('defer[known]',
	   $config_load_max, $config_sleeping_max,
	   $config_load_defer_mul, $config_load_defer_adj, $config_load_defer_min, $config_load_defer_max,
	   $config_load_wait_mul,  $config_load_wait_adj,  $config_load_wait_min,  $config_load_wait_max,
	   $current_load, $load_get,
	   $sleeping_incr, $sleeping_decr, $go_to_sleep_sub);
      push @act, $act if defined $act;
      return (1, $all_act) if $yes;
    };
  }
  elsif ($is_assumed_bot_sub->($user_agent)) {
    my ($yes, $act) = _tell_load_defer
	('defer[assumed]',
	 $config_load_max, $config_sleeping_max,
	 $config_load_defer_mul, $config_load_defer_adj, $config_load_defer_min, $config_load_defer_max,
	 $config_load_wait_mul,  $config_load_wait_adj,  $config_load_wait_min,  $config_load_wait_max,
	 $current_load, $load_get,
	 $sleeping_incr, $sleeping_decr, $go_to_sleep_sub);
    return (1, $act) if $yes;
  }
  return;
}

sub tell_bot_throttle {
  my ($remote_ip, $user_agent,
      $current_load, $load_get,
      $sleeping_incr, $sleeping_decr, $go_to_sleep_sub,
      $memcache_get, $memcache_set) = @_;
  return _tell_bot_throttle($BOT_THROTTLE,
			    $BOT_LONE_THROTTLE_TIME, $BOT_ALL_THROTTLE_TIME,
			    $LOAD_MAX, $SLEEPING_MAX,
			    $LOAD_DEFER_MUL, $LOAD_DEFER_ADJ, $LOAD_DEFER_MIN, $LOAD_DEFER_MAX,
			    $LOAD_WAIT_MUL,  $LOAD_WAIT_ADJ,  $LOAD_WAIT_MIN,  $LOAD_WAIT_MAX,
			    Bibliotech::Util::time(),
			    $remote_ip, $user_agent,
			    \&is_user_agent_a_known_bot, \&is_user_agent_an_assumed_bot,
			    $current_load, $load_get,
			    $sleeping_incr, $sleeping_decr,
			    $go_to_sleep_sub,
			    $memcache_get, $memcache_set);
}

sub do_bot_throttle {
  my $self     = shift;
  my $r        = $self->request;
  my $memcache = $self->memcache;
  my $log      = $self->log;
  my ($yes, $act) = tell_bot_throttle($r->connection->remote_ip || undef,
				      $r->header_in('User-Agent') || undef,
				      $self->load,
				      sub { $memcache->get('LOAD') },
				      sub { $memcache->add('SLEEPING' => 0);
					    $memcache->incr('SLEEPING') },
				      sub { $memcache->decr('SLEEPING') },
				      sub { my ($logname, $seconds) = @_;
					    $log->info("$logname is deferring a bot $seconds seconds");
					    sleep($seconds); },
				      sub { $memcache->get(@_) },
				      sub { $memcache->set(@_) },
				    );
  return $act->($r, $log) if defined $act;
  return $yes ? HTTP_SERVICE_UNAVAILABLE : 0;
}

sub _is_user_agent_a_known_bot {
  my ($user_agent, $config_bot_list, $config_blank_is_bot) = @_;
  return '-' if !$user_agent and $config_blank_is_bot;
  return first { $user_agent =~ /$_/ } list_from_undef_scalar_or_arrayref($config_bot_list);
}

sub is_user_agent_a_known_bot {
  my $user_agent = shift;
  return _is_user_agent_a_known_bot($user_agent, $THROTTLE_FOR, 1);
}

sub _is_user_agent_an_assumed_bot {
  my ($user_agent, $config_human_list, $config_blank_is_bot) = @_;
  return '-' if !$user_agent and $config_blank_is_bot;
  return if any { $user_agent =~ /$_/ } list_from_undef_scalar_or_arrayref($config_human_list);
  return $user_agent;
}

sub is_user_agent_an_assumed_bot {
  my $user_agent = shift;
  return _is_user_agent_an_assumed_bot($user_agent, $ANTI_THROTTLE_FOR, 1);
}

sub revise_hit_stack {
  my ($now, $config_time, $hits_ref) = @_;
  my $cutoff = $now - $config_time;
  return ((grep { $_ > $cutoff } list_from_undef_scalar_or_arrayref($hits_ref)), $now);
}

sub _is_rapid_fire_by_hit_stack {
  my ($now, $config_time, $config_max_hits, $hits_ref_get, $hits_ref_set) = @_;
  my @hits = revise_hit_stack($now, $config_time, $hits_ref_get->());
  $hits_ref_set->(\@hits, $config_time);
  return @hits > $config_max_hits;
}

sub is_rapid_fire_by_hit_stack {
  my ($now, $config_time, $config_max_hits, $hits_ref_get, $hits_ref_set) = @_;
  return _is_rapid_fire_by_hit_stack($now,
				     $config_time, $config_max_hits,
				     $hits_ref_get, $hits_ref_set);
}

sub _tell_rapid_fire_by_hit_stack_throttle {
  my ($logname, $switch, $time, $hits, $config_api_list, $now, $who, $user_agent, $memcache_get, $memcache_set) = @_;
  return unless $switch;
  return if any { $user_agent =~ /$_/ } list_from_undef_scalar_or_arrayref($config_api_list);
  my $key = Bibliotech::Cache::Key->new(class => __PACKAGE__,
					method => 'query_handler',
					id => 'dt',
					id => $who);
  if (is_rapid_fire_by_hit_stack($now, $time, $hits,
				 sub { $memcache_get->($key) || [] },
				 sub { $memcache_set->($key, @_) }
				 )) {
    return (1, sub { my ($r, $log) = @_;
		     $r->err_headers_out->set('Retry-After' => $time);
		     $log->info("$logname is holding back a host due to rapid fire: $who");
		     return HTTP_SERVICE_UNAVAILABLE;
		   });
  }
  return;
}

sub tell_rapid_fire_by_hit_stack_throttle {
  my ($logname, $who, $user_agent, $memcache_get, $memcache_set) = @_;
  return _tell_rapid_fire_by_hit_stack_throttle($logname,
						$DYNAMIC_THROTTLE,
						$DYNAMIC_THROTTLE_TIME, $DYNAMIC_THROTTLE_HITS,
						$DYNAMIC_THROTTLE_NEVER_FOR,
						Bibliotech::Util::time(),
						$who, $user_agent,
						$memcache_get, $memcache_set);
}

sub do_dynamic_throttle {
  my $self     = shift;
  my $r        = $self->request;
  my $memcache = $self->memcache;
  my $user     = $self->user;
  my $agent    = $r->header_in('User-Agent');
  my $who      = (defined $user ? 'user '.$user->username.' ('.$user->id.')'
		                : join(':', $r->connection->remote_ip, $agent || '-'));
  my ($yes, $act) = tell_rapid_fire_by_hit_stack_throttle('dynamic',
							  $who,
							  $agent,
							  sub { $memcache->get(@_) },
							  sub { $memcache->set(@_) },
							  );
  return $act->($r, $self->log) if defined $act;
  return $yes ? HTTP_SERVICE_UNAVAILABLE : 0;
}
