#!/usr/bin/perl

use Test::More tests => 64;
use Test::Exception;
use strict;
use warnings;

BEGIN {
  use_ok('Bibliotech::Parser');
}

$Bibliotech::Parser::SKIP_VALIDATE = 1;
my $p = Bibliotech::Parser->new;

ok($p->check_user_format('username'),  	 'username');
ok(!$p->check_user_format('group'),      'username of gang keyword disallowed');
ok(!$p->check_user_format('group/crap'), 'username starting with gang keyword and slash disallowed');
ok($p->check_user_format('groupify'),    'username starting with gang keyword');
ok(!$p->check_user_format('tag'),      	 'username of tag keyword disallowed');
ok(!$p->check_user_format('tag/crap'), 	 'username starting with tag keyword and slash disallowed');
ok($p->check_user_format('tagify'),      'username starting with tag keyword');
ok(!$p->check_user_format('date'),     	 'username of date keyword disallowed');
ok(!$p->check_user_format('date/crap'),	 'username starting with date keyword and slash disallowed');
ok($p->check_user_format('dateify'),     'username starting with date keyword');
ok(!$p->check_user_format('uri'),     	 'username of bookmark keyword disallowed');
ok(!$p->check_user_format('uri/crap'),	 'username starting with bookmark keyword and slash disallowed');
ok($p->check_user_format('uriify'),      'username starting with bookmark keyword');

sub test_tag_list {
  my ($spec, $result, $special_name) = @_;
  is_deeply(scalar $p->tag_list($spec), $result, $special_name ? 'tag_list - '.$special_name : 'tag_list: '.$spec);
}

test_tag_list('web_2.0',
	      ['web_2.0']);
test_tag_list('web_2.0 software',
	      ['web_2.0', 'software']);
test_tag_list('web_2.0 software "in-house development"',
	      ['web_2.0', 'software', 'in-house development']);
test_tag_list('web_2.0, software, "in-house development"',
	      ['web_2.0', 'software', 'in-house development']);
test_tag_list('web_2.0,software,"in-house development"',
	      ['web_2.0', 'software', 'in-house development']);
test_tag_list('"urinary incontinence"',
	      ['urinary incontinence']);
test_tag_list('perl uri',
	      [],
	      'uri is not a valid tag');
test_tag_list('"alpha-adrenergic antagonists" "multiple-system atrophy" "self-catheterization" surgery "urinary retention"',
	      ['alpha-adrenergic antagonists', 'multiple-system atrophy', 'self-catheterization', 'surgery', 'urinary retention']);

sub test_command {
  my ($uri, $canonical, $page, $filters_used) = @_;
  my $command = $p->parse($uri);
  is($command->canonical_uri('/', undef, 1), $canonical, "parse: $uri (canonical)");
  is($command->page_or_inc, $page,                       "parse: $uri (page)");
  is(join(',', $command->filters_used), $filters_used,   "parse: $uri (filters used)");
}

test_command('/',
	     '/home',
	     'home',
	     '');
test_command('/user/john',
	     '/user/john',
	     'recent',
	     'user');
test_command('/group/babysitters',
	     '/group/babysitters',
	     'recent',
	     'gang');
test_command('/tag/perl',
	     '/tag/perl',
	     'recent',
	     'tag');
test_command('/date/2006-01-01',
	     '/date/2006-01-01',
	     'recent',
	     'date');
test_command('/uri/e21723e6bc30a790312c9deec16bfa2e',
	     '/uri/e21723e6bc30a790312c9deec16bfa2e',
	     'recent',
	     'bookmark');
test_command('/user/john/tag/perl',
	     '/user/john/tag/perl',
	     'recent',
	     'user,tag');
test_command('/recent/user/john',
	     '/user/john',
	     'recent',
	     'user');
test_command('/recent/user/john/tag/perl',
	     '/user/john/tag/perl',
	     'recent',
	     'user,tag');
test_command('/wiki/User:john',
	     '/wiki/User:john',
	     'wiki',
	     '');
test_command('/user/john?start=10',
	     '/user/john?start=10',
	     'recent',
	     'user');
test_command('/user/john?start=10&num=50',
	     '/user/john?start=10&num=50',
	     'recent',
	     'user');
test_command('/user/john?num=50&start=10',
	     '/user/john?start=10&num=50',
	     'recent',
	     'user');
test_command('/export/user/john',
	     '/export/user/john',
	     'export',
	     'user');
