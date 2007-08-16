#!/usr/bin/perl

use strict;
use warnings;

use lib '..';
use Bibliotech::Fake;
use Bibliotech::Util;
use URI;
use Data::Dumper;

my $plugin = shift @ARGV;

die "No plug-in specified, so I can't do anything\n" unless $plugin;

$plugin = 'Bibliotech::CitationSource::'.$plugin;

eval "use $plugin";

die $@ if $@;

my $b = Bibliotech::Fake->new;
my $c = $plugin->new($b);

while (<STDIN>)
{
    chomp;
    my $uri = URI->new($_);
    my $cache;
    my $get = sub { return Bibliotech::Util::get($uri, $b, \$cache) };
    print "Testing: \'$uri\'\n";
    my $understands_code = $c->understands($uri, $get);
    show_err_and_warn($c);
    unless ($understands_code) {
      print "Don't understand, skipping.\n\n";
      next;
    }
    if ($understands_code == -1) {
      print "Transient error reported.\n";
      next;
    }
    if ($understands_code != 1) {
      print "URI understood, but lesser score reported (${understands_code})\n";
    }
    my $new_uri = $c->filter($uri, $get);
    show_err_and_warn($c);
    if(!defined $new_uri) {
      print "No change from filter.\n";
    }
    elsif($new_uri) {
      print "Filter: $new_uri\n";
      $uri = $new_uri;
      my $new_cache;
      $get = sub { return Bibliotech::Util::get($uri, $b, \$new_cache) };
    }
    else {
      print "Filter returned empty string - abort.\n";
      next;
    }
    my $citations = $c->citations($uri, $get);
    show_err_and_warn($c);
    unless ($citations) {
      print "No citations.\n\n";
      next;
    }
    my $result = $citations->fetch;
    print "DOI: ", $result->identifier('doi')||'', "\n";
    print "Title: ", $result->title||'', "\n";
    print "Journal: ", ($result->journal ? $result->journal->name : ''), "\n";
    print "Volume: ", $result->volume||'', "\n";
    print "Issue: ", $result->issue||'', "\n";
    print "Page: ", $result->page||'', "\n";
    print "Date: ", $result->date||'', "\n";
    if(my $authors = $result->authors) {
	my @author_str;
	$authors->foreach(sub{ push @author_str, extract_name($_); });
	print 'Authors (', scalar @author_str, '): ', join(', ', @author_str), "\n";
    }
    else {
	print "No Authors", "\n";
    }
    print "\n";
    sleep 3;
}

sub extract_name {
  my $author = shift;
  my $get = sub { my $field = shift;
		  return unless $author->can($field);
		  return $author->$field; };
  my $or  = sub { foreach (@_) { my $value = $get->($_);
				 return $value if defined $value; }
		  return; };
  return join(' ', grep { $_ } $or->('forename', 'firstname'), $or->('surname', 'lastname'));
}

sub show_err_and_warn {
  my $c = shift;
  if (my $errstr = $c->errstr) { 
    $errstr =~ s/\n$//;
    print "Error from module: $errstr\n";
  }
  if (my $warnstr = $c->warnstr) {
    $warnstr =~ s/\n$//;
    print "Debug warning from module: $warnstr\n";
  }
}
