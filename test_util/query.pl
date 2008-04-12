#!/usr/bin/perl
use warnings;
use strict;
use Bibliotech::Fake;
use Bibliotech::Page;
use Bibliotech::Page::Standard;
use Bibliotech::Query;
use Bibliotech::Parser;

my $uri = shift @ARGV or die "provide uri, e.g. /user/someone\n";
my $fmt = shift @ARGV || 'txt';

my $parser = Bibliotech::Parser->new;
my $command = $parser->parse($uri, 'GET');
my $bibliotech = Bibliotech::Fake->new;
my $query = Bibliotech::Query->new($command, $bibliotech);
$bibliotech->query($query);
my $page = Bibliotech::Page::Recent->new({bibliotech => $bibliotech});
my $func = $fmt.'_content';
print $page->$func."\n";
