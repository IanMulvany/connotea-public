#!/usr/bin/perl

# Tag creation and deletion testing
# Also test user tag annotations

use Test::More tests => 40;
use Test::Exception;
use strict;
use warnings;

BEGIN {
  use_ok('Bibliotech::TestUtils') or exit;
}

is_table_empty_or_bail('Bibliotech::User');
is_table_empty_or_bail('Bibliotech::Tag');

my $bibliotech = get_test_bibliotech_object_1_test();
my $user       = get_test_user_7_tests($bibliotech);
my $tag        = simple_create_3_tests('Bibliotech::Tag' => {name => 'test'});
my $comment    = simple_create_3_tests('Bibliotech::Comment' => {entry => 'This is a comment.'});
my $annotate   = simple_create_3_tests('Bibliotech::User_Tag_Annotation' => {user => $user, tag => $tag, comment => $comment});

$tag->delete;
# annotation and comment should be gone now as well as tag
is_table_empty('Bibliotech::Tag');
is_table_empty('Bibliotech::User_Tag_Annotation');
is_table_empty('Bibliotech::Comment');

$tag           = simple_create_3_tests('Bibliotech::Tag' => {name => 'hooray'});
$comment       = simple_create_3_tests('Bibliotech::Comment' => {entry => 'New comment.'});
$annotate      = simple_create_3_tests('Bibliotech::User_Tag_Annotation' => {user => $user, tag => $tag, comment => $comment});

my $bookmark   = simple_create_3_tests('Bibliotech::Bookmark' => {url => 'test:1'});
my $post       = simple_create_3_tests('Bibliotech::User_Bookmark' => {user => $user, bookmark => $bookmark});

lives_ok { $post->link_tag($tag) } 'link_tag';
is(join(' ', map { $_->name } $post->tags), 'hooray', 'tagged hooray');

my $tag2       = simple_create_3_tests('Bibliotech::Tag' => {name => 'bye'}, 2);

lives_ok { $bibliotech->retag($user, $tag, $tag2) } 'retag';
is(join(' ', map { $_->name } $post->tags), 'bye', 'tagged bye');

$user->delete;
is_table_empty('Bibliotech::User');
is_table_empty('Bibliotech::Tag');
is_table_empty('Bibliotech::User_Tag_Annotation');
is_table_empty('Bibliotech::Comment');
