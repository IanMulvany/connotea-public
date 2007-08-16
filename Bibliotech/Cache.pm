# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Cache class wraps CPAN module Cache::Memcached.

package Bibliotech::Cache;
use strict;
use base 'Cache::Memcached';
use fields 'log';
use Bibliotech::Config;

our $MEMCACHED_SERVERS = Bibliotech::Config->get('MEMCACHED_SERVERS') || [ '127.0.0.1:11211' ];

sub new {
  my $class = shift;
  my $options = shift || {};
  $options->{servers} ||= $MEMCACHED_SERVERS;
  $options->{compress_threshold} ||= 1_048_576; # 1 meg
  my $log = $options->{log};
  delete $options->{log};
  my $self = $class->SUPER::new($options, @_);
  $self->{log} = $log;
  return $self;
}

sub log {
  shift->{log};
}

# save a value in the memchae
sub set_with_last_updated {
  my ($self, $key, $value, $last_updated) = @_;
  my $key_s = "$key";  # in case the key is an object, flatten it to a string value
  my $log = $self->log;
  $log->debug("cache: set $key_s") if $log;
  return $self->set($key_s => Bibliotech::Cache::Value->new($value, $last_updated), 43200);  # drop after 12 hours
}

# mark a value in the memcache with a "calc lock" which indicates to other processes that we're figuring it out
# those processes may then elect to simply idle and wait for us to finish (see below)
sub set_calc {
  my ($self, $key, $existing_cache_entry) = @_;
  my $key_s = "$key";  # in case the key is an object, flatten it to a string value
  my $log = $self->log;
  $log->debug("cache: calc $key_s");
  my $cache_entry;
  if ($existing_cache_entry) {
    $cache_entry = $existing_cache_entry;
    $cache_entry->set_calc;
  }
  else {
    $cache_entry = Bibliotech::Cache::Value->new_calc;
  }
  return $self->set($key_s => $cache_entry, 1800);  # drop after half an hour (we expect the calc to be finished long before then)
}

# get a value from memcache
# the memcache return value will be of type Bibliotech::Cache::Value (defined below) that contains the value, a timestamp, and a calc lock
# will check the timestamp based on a provided current last_updated timestamp and a lazy update period (expressed as seconds)
# will check the calc lock and wait up to 20 seconds for another process to finish the calculation and provide a value
# in scalar context returns the cached value
# in list context also returns the cached timestamp
sub get_with_last_updated {
  my ($self, $key, $last_updated, $lazy_update, $set_calc) = @_;
  my $key_s = "$key";  # in case the key is an object, flatten it to a string value
  my $log = $self->log;
  $log->debug("cache: get $key_s") if $log;
  my $cache_entry = $self->get($key_s);
  if (defined $cache_entry) {
    # if the data is current, we don't care whether the calc lock is set or not
    return wantarray ? ($cache_entry->value, $cache_entry->last_updated) : $cache_entry->value
	if $cache_entry->is_current($last_updated, $lazy_update, $key_s);
    #$log->debug("cache: not current data received for cache key $key_s") if $log;
    # otherwise, we do care
    if (my $other_pid = $cache_entry->is_calc) {
      $log->debug("cache: waiting on $other_pid for cache key $key_s") if $log;
      for (my $i = 1; $i <= 20; $i++) {
	sleep 1;
	next unless $cache_entry = $self->get($key_s);
	next if $cache_entry->is_calc;
	if ($cache_entry->is_current($last_updated, $lazy_update)) {
	  $log->debug("cache: obtained value from $other_pid on attempt $i") if $log;
	  return wantarray ? ($cache_entry->value, $cache_entry->last_updated) : $cache_entry->value;
	}
	last;  # is_calc went false but value is not current
      }
    }
  }
  #else {
    #$log->debug("cache: no entry received for cache key $key_s") if $log;
  #}
  $self->set_calc($key => $cache_entry) if $set_calc;
  return wantarray ? (undef, undef) : undef;
}

# this will prepend debug strings to returned HTML values to visually report that they came from the cache
sub get_with_last_updated_debug_wrapper {
  my ($self, $key, $last_updated, $lazy_update, $set_calc) = @_;
  my ($value, $cache_last_updated) = $self->get_with_last_updated($key, $last_updated, $lazy_update, $set_calc);
  return undef unless defined $value;
  my $cache_last_updated_str = localtime($cache_last_updated);
  my $debug = "\n<div class=\"debug\">Loaded from memcache on [$key] stamped [$cache_last_updated_str ($cache_last_updated)].</div>\n";
  return $debug.$value unless ref $value;
  return $value unless ref $value eq 'Bibliotech::Page::HTML_Content';
  my $html_parts = $value->html_parts;
  if (ref $html_parts->{main}) {
    unshift @{$html_parts->{main}}, $debug;
  }
  else {
    $html_parts->{main} = $debug.$html_parts->{main};
  }
  return $value;
}


package Bibliotech::Cache::Value;
use strict;
use Bibliotech::Util;

sub new {
  my ($class, $value, $last_updated) = @_;
  $last_updated = $last_updated->epoch if ref $last_updated;
  return bless [$value, $last_updated, 0], ref $class || $class;
}

sub value {
  shift->[0];
}

sub last_updated {
  shift->[1];
}

sub is_current {
  my ($self, $current_last_updated, $lazy_update, $key, $log) = @_;
  $current_last_updated = $current_last_updated->epoch if ref $current_last_updated;
  my $cached_last_updated = $self->last_updated;
  if ($log) {
    $log->debug("  is_current $key") if $key;
    $log->debug("  \$current_last_updated = $current_last_updated");
    $log->debug("  \$cached_last_updated  = $cached_last_updated");
    $log->debug("  \$cached_last_updated >= \$current_last_updated ... ".($cached_last_updated >= $current_last_updated ? 'true' : 'false'));
  }
  return 1 if $cached_last_updated >= $current_last_updated;
  $log->debug("  \$lazy_update = $lazy_update") if $log;
  my $now = Bibliotech::Util::time();
  $log->debug("  \$now         = $now") if $log;
  $log->debug("  \$cached_last_updated + (\$lazy_update ? (\$lazy_update != 1 ? \$lazy_update : 7200) : 0) >= \$now ... ".($cached_last_updated + ($lazy_update ? ($lazy_update != 1 ? $lazy_update : 7200) : 0) >= $now ? 'true' : 'false')) if $log;
  return 1 if $cached_last_updated + ($lazy_update ? ($lazy_update != 1 ? $lazy_update : 7200) : 0) >= $now;
  $log->debug("  return 0 (is not current)") if $log;
  return 0;
}

sub is_calc {
  shift->[2];
}

sub set_calc {
  my $self = shift;
  $self->[2] = $$;
  return $self;
}

sub new_calc {
  my $self = shift->new(undef, 0);
  return $self->set_calc;
}


package Bibliotech::Cache::Key;
use strict;
use Data::Dumper;  # not just for debugging, really used
use Encode qw(encode_utf8);

our $JOIN = '!';

sub quick {
  shift;
  join($JOIN, @_);
}

sub new {
  my $self = shift;
  my $bibliotech = UNIVERSAL::isa($_[0], 'Bibliotech') ? shift : undef;
  my @values;
  while (@_) {
    my $dep   = shift or die 'no dep';
    my $value = shift;
    push @values, $self->$dep($value, $bibliotech);
  }
  (my $key = encode_utf8(join($JOIN, @values))) =~ s|\s|^|g;
  return $key;
}

sub class {
  $_[1];
}

sub method {
  $_[1] || 'html_content';
}

sub user {
  $_[1] || $_[2]->request->user || 'visitor';
}

sub effective {
  return $_[1] if $_[1] && !ref $_[1];
  $_[0]->calc_effective($_[1]->[0] || $_[2]->user, $_[1]->[1]);
}

sub path {
  $_[1] || $_[2]->canonical_path_for_cache_key;
}

sub path_without_args {
  return $_[1] if $_[1];
  my $path_with_args = $_[2]->canonical_path_for_cache_key;
  (my $path_stripped = "$path_with_args") =~ s/\?.+?$//;
  my $path = new URI ($path_stripped);
  $path->query_param($_ => $path_with_args->query_param($_)) foreach ('uri', 'q');
  return $path;
}

sub options {
  return '' if !$_[1] or !keys %{$_[1]};
  my $dd = new Data::Dumper([$_[1]]);
  $dd->Indent(0);
  $dd->Terse(1);
  $dd->Quotekeys(0);
  my $ops = $dd->Dump;
  $ops =~ s/^\{(.*)\}$/$1/;
  $ops =~ s/ => /=/g;
  return $ops;
}

sub id {
  $_[1] or die 'tried to create a cache key with an undefined id';
}

sub value {
  $_[1]->[0].'='.$_[1]->[1];
}

sub calc_effective {
  my ($self, $user_or_user_id, $another_user_or_user_id) = @_;
  my ($user, $user_id, $another_user, $another_user_id);
  if (UNIVERSAL::isa($user_or_user_id, 'Bibliotech::User')) {
    $user = $user_or_user_id;
    $user_id = $user->user_id;
  }
  else {
    $user_id = $user_or_user_id;
  }
  if (UNIVERSAL::isa($another_user_or_user_id, 'Bibliotech::User')) {
    $another_user = $another_user_or_user_id;
    $another_user_id = $another_user->user_id;
  }
  else {
    $another_user_id = $another_user_or_user_id;
  }
  return 'same' if $user_id == $another_user_id;
  my $quick = $Bibliotech::Apache::QUICK{'Bibliotech::Cache::calc_effective'}->{$user_id}->{$another_user_id};
  return $quick if defined $quick;
  my $gangs = '';
  $user = Bibliotech::User->retrieve($user_id) unless defined $user;
  if (defined $user) {
    my $user_gangs = new Set::Array (map($_->gang_id, $user->gangs));
    $another_user = Bibliotech::User->retrieve($another_user_id) unless defined $another_user;
    if (defined $another_user) {
      my $another_user_gangs = new Set::Array (map($_->gang_id, $another_user->gangs));
      $user_gangs->intersection($another_user_gangs);
    }
    $gangs = join(',', @{$user_gangs});
  }
  my $value = 'another:'.$gangs;
  $Bibliotech::Apache::QUICK{'Bibliotech::Cache::calc_effective'}->{$user_id}->{$another_user_id} = $value;
  return $value;
}

1;
__END__
