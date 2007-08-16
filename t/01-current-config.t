#!/usr/bin/perl

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

use strict;
use warnings;
use Test::More tests => 50;
use Test::Exception;

my $check_optionals = $ENV{BIBTEST}||'' =~ /optionals/;

BEGIN {
  ok(-e '/etc/bibliotech.conf', 'config file exists') or exit;
  use_ok('Bibliotech::Config') or exit;
}

my $site_name = Bibliotech::Config->get('SITE_NAME');
ok($site_name, 'SITE_NAME specified');

my $site_email = Bibliotech::Config->get('SITE_EMAIL');
ok($site_email, 'SITE_EMAIL specified');
ok($site_email =~ /.+\@\w+\.\w+/, 'SITE_EMAIL appears to be an email address');

my $dbi_connect = Bibliotech::Config->get('DBI_CONNECT');
ok($dbi_connect, 'DBI_CONNECT specified');
ok($dbi_connect =~ /^dbi:mysql/, 'DBI_CONNECT appears to be a MySQL connect string');

my $dbi_username = Bibliotech::Config->get('DBI_USERNAME');
ok($dbi_username, 'DBI_USERNAME specified');
ok($dbi_username ne 'root', 'DBI_USERNAME is not root');

my $pid_file = Bibliotech::Config->get('PID_FILE');
ok($pid_file, 'PID_FILE specified');
(my $pid_file_path = $pid_file) =~ s|/[^/]*$||;
ok(-e $pid_file_path, 'PID_FILE path exists');
ok(-d $pid_file_path, 'PID_FILE path is a directory');

my $sendmail = Bibliotech::Config->get('SENDMAIL');
ok($sendmail, 'SENDMAIL specified');
ok(-e $sendmail, 'SENDMAIL exists');
ok(-f $sendmail, 'SENDMAIL is a file');
ok(-x $sendmail, 'SENDMAIL is executable');

my $user_cookie_secret = Bibliotech::Config->get('USER_COOKIE_SECRET');
ok($user_cookie_secret, 'USER_COOKIE_SECRET is specified');
ok($user_cookie_secret ne 'secretsecret', 'USER_COOKIE_SECRET has been customized to a real secret');

my $user_verifycode_secret = Bibliotech::Config->get('USER_VERIFYCODE_SECRET');
ok($user_verifycode_secret, 'USER_VERIFYCODE_SECRET is specified');
ok($user_verifycode_secret ne 'veryverysecret', 'USER_VERIFYCODE_SECRET has been customized to a real secret');

my $log_file = Bibliotech::Config->get('LOG_FILE');
ok($log_file, 'LOG_FILE is specified');
(my $log_file_path = $log_file) =~ s|/[^/]*$||;
ok(-e $log_file_path, 'LOG_FILE path exists');
ok(-d $log_file_path, 'LOG_FILE path is a directory');

SKIP: {
  skip 'you did not ask for optional settings to be checked', 27 unless $check_optionals;

  # DBI_PASSWORD could legally be absent if it was not required for local connection
  my $dbi_password = Bibliotech::Config->get('DBI_PASSWORD');
  ok($dbi_password, 'DBI_PASSWORD specified');

  # DBI_SEARCH could legally be absent if search was not offered
  my $dbi_search = Bibliotech::Config->get('DBI_SEARCH');
  ok($dbi_search, 'DBI_SEARCH specified');

  # MEMCACHED_SERVERS could legally be absent and run on default
  my $memcached_servers = Bibliotech::Config->get('MEMCACHED_SERVERS');
  ok($memcached_servers, 'MEMCACHED_SERVERS specified');
  isa_ok($memcached_servers, 'ARRAY', 'MEMCACHED_SERVERS');

  # TEMPLATE_ROOT could legally be absent and run on default
  my $template_root = Bibliotech::Config->get('TEMPLATE_ROOT');
  ok(defined $template_root, 'TEMPLATE_ROOT specified');

  # CLIENT_SIDE_HTTP_CACHE could legally be absent and run on default
  my $client_side_http_cache = Bibliotech::Config->get('CLIENT_SIDE_HTTP_CACHE');
  ok(defined $client_side_http_cache, 'CLIENT_SIDE_HTTP_CACHE specified');

  # TIME_ZONE_ON_DB_HOST could legally be absent and run on default
  my $time_zone_on_db_host = Bibliotech::Config->get('TIME_ZONE_ON_DB_HOST');
  ok(defined $time_zone_on_db_host, 'TIME_ZONE_ON_DB_HOST specified');

  # TIME_ZONE_PROVIDED could legally be absent and run on default
  my $time_zone_provided = Bibliotech::Config->get('TIME_ZONE_PROVIDED');
  ok(defined $time_zone_provided, 'TIME_ZONE_PROVIDED specified');

  # CITATION_MODULES could legally be absent and you'd have no citation ability
  my $citation_modules = Bibliotech::Config->get('CITATION_MODULES');
  ok($citation_modules, 'CITATION_MODULES specified');
  isa_ok($citation_modules, 'ARRAY', 'CITATION_MODULES');

  # IMPORT_MODULES could legally be absent and you'd have no import ability
  my $import_modules = Bibliotech::Config->get('IMPORT_MODULES');
  ok($import_modules, 'IMPORT_MODULES specified');
  isa_ok($import_modules, 'ARRAY', 'IMPORT_MODULES');

  # RESERVED_PREFIXES could legally be absent and no names would be rejected
  my $reserved_prefixes = Bibliotech::Config->get('RESERVED_PREFIXES');
  ok($reserved_prefixes, 'RESERVED_PREFIXES specified');
  isa_ok($reserved_prefixes, 'ARRAY', 'RESERVED_PREFIXES');

  # GLOBAL_CSS_FILE could legally be absent and run on default
  my $global_css_file = Bibliotech::Config->get('GLOBAL_CSS_FILE');
  ok($global_css_file, 'GLOBAL_CSS_FILE specified');

  # SERVICE_PAUSED could legally be absent and run on default
  my $service_paused = Bibliotech::Config->get('SERVICE_PAUSED');
  ok(defined $service_paused, 'SERVICE_PAUSED specified');
  ok(!$service_paused, 'SERVICE_PAUSED is false');

  # SERVICE_NEVER_PAUSED_FOR could legally be absent and no IP's would be treated specially
  my $service_never_paused_for = Bibliotech::Config->get('SERVICE_NEVER_PAUSED_FOR');
  ok($service_never_paused_for, 'SERVICE_NEVER_PAUSED_FOR specified');
  isa_ok($service_never_paused_for, 'ARRAY', 'SERVICE_NEVER_PAUSED_FOR');

  # FRESH_VISITOR_LAZY_UPDATE could legally be absent and run on default
  my $fresh_visitor_lazy_update = Bibliotech::Config->get('FRESH_VISITOR_LAZY_UPDATE');
  ok(defined $fresh_visitor_lazy_update, 'FRESH_VISITOR_LAZY_UPDATE specified');

  # TITLE_OVERRIDE could legally be absent and all titles would be dynamic
  my $title_override = Bibliotech::Config->get('TITLE_OVERRIDE');
  ok($title_override, 'TITLE_OVERRIDE specified');
  isa_ok($title_override, 'HASH', 'TITLE_OVERRIDE');

  # THROTTLE could legally be absent and run on default
  my $throttle = Bibliotech::Config->get('THROTTLE');
  ok(defined $throttle, 'THROTTLE specified');

  # THROTTLE_FOR could legally be absent and no agents would be treated specially
  my $throttle_for = Bibliotech::Config->get('THROTTLE_FOR');
  ok($throttle_for, 'THROTTLE_FOR specified');
  isa_ok($throttle_for, 'ARRAY', 'THROTTLE_FOR');

  # THROTTLE_TIME could legally be absent and run on default
  my $throttle_time = Bibliotech::Config->get('THROTTLE_TIME');
  ok($throttle_time, 'THROTTLE_TIME specified');
  ok($throttle_time =~ /^\d+$/ && $throttle_time > 0, 'THROTTLE_TIME is a positive number');
}
