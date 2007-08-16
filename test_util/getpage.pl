#!/usr/bin/perl
use strict;
use URI;
use Bibliotech::Util;

my $switch  = shift @ARGV or die "Please specify -c for content or -t for title, followed by URL.\n";
my $uri_str = shift @ARGV or die "Please provide a URL.\n";
my $uri = URI->new($uri_str);
my ($response, $content, $html_title) = Bibliotech::Util::get($uri);
print $response->status_line, "\n";
print ($switch eq '-t' ? $html_title : $content), "\n";
