#!/usr/bin/perl

# Test script that checks low-level database access.

use Test::More tests => 28;
use strict;
use warnings;

BEGIN {
    use_ok('Bibliotech::Config', file => $ENV{CONFIG}) or exit;
    use_ok('Bibliotech::DBI') or exit;
}

my $dbh = Bibliotech::DBI->db_Main;
ok(defined $dbh, 'database handle defined');

do {
  my $sth = $dbh->prepare('show tables');
  ok(defined $sth, 'statement prepare for show tables');
  $sth->execute;
  my %table = map { $_->[0] => 1; } @{$sth->fetchall_arrayref};
  foreach (qw/author bookmark bookmark_details citation citation_author comment gang journal tag
              article user user_article user_article_comment user_article_details
              user_gang user_tag_annotation/) {
    ok($table{$_}, $_.' table exists ('.$Bibliotech::DBI::DBI_CONNECT.')');
  }
};

do {
  my $repl   = $Bibliotech::DBI::DBI_SEARCH_DOT_OR_BLANK.'user';
  my $count  = sub { my @arr = $dbh->selectrow_array('select count(*) from '.shift); $arr[0]; };
  my $insert = sub { $dbh->do('insert into user (user_id, username) values (?, ?)', undef, 1, 'johnsmith'); };
  my $delete = sub { $dbh->do('delete from user where user_id = ?', undef, 1); };
  is($count->('user'), 0, '0 users to start');
  is($count->($repl),  0, '0 users to start (replicated database)');
  ok($insert->(),         'insert user');
  is($count->('user'), 1, '1 user after insert');
  is($count->($repl),  1, '1 user after insert (replicated database; is replication on?)');
  ok($delete->(),         'delete user');
  is($count->('user'), 0, '0 users after delete');
  is($count->($repl),  0, '0 users after delete (replicated database; is replication on?)');
};
