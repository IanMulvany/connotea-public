#!/usr/bin/perl
use strict;
use warnings;
use URI;
use lib '..';
use Bibliotech::Fake;
use Bibliotech::Util;
use Bibliotech::Plugin;

my $plugin = shift @ARGV or die "No type specified.\n";
$plugin = undef if $plugin =~ /^(?:auto)?detect$/i;

my $b = Bibliotech::Fake->new;
my $c;
if ($plugin) {
  my $class = 'Bibliotech::CitationSource::'.$plugin;
  eval "use $class"; die "cannot use $class: $@" if $@;
  $c = $class->new($b) or die 'no citation source object: '.$plugin;
}
my $p = sub { process_uri_str(shift, $b, $c) };
if (@ARGV) {
  $p->($_) foreach (@ARGV);
}
else {
  print "Ready.\n";
  $p->(do { chomp; $_; }) while (<>);
}

sub process_uri_str {
  my ($uri_str, $b, $c) = @_;
  my $uri = URI->new($uri_str);
  process_uri($uri, $b, sub { make_getter(shift, $b) }, $c);
}

sub make_getter {
  my ($uri, $b) = @_;
  my $cache;
  return sub { Bibliotech::Util::get($uri, $b, \$cache) };
}

sub process_uri {
  my ($uri, $b, $make_get, $c) = @_;
  print "Testing: \'$uri\'\n";
  my $get = $make_get->($uri);
  $c = scan_uri($uri, $b, $get) unless defined $c;
  my $understands_code = $c->understands($uri, $get);
  show_err_and_warn($c);
  unless ($understands_code) {
    print "Don't understand, skipping.\n\n";
    return;
  }
  if ($understands_code == -1) {
    print "Transient error reported.\n";
    return;
  }
  if ($understands_code != 1) {
    print "URI understood, but lesser score reported (${understands_code})\n";
  }
  my $new_uri = $c->filter($uri, $get);
  show_err_and_warn($c);
  if (!defined $new_uri) {
    print "No change from filter.\n";
  }
  elsif ($new_uri) {
    print "Filter: $new_uri\n";
    $uri = $new_uri;
    $get = $make_get->($uri);
  }
  else {
    print "Filter returned empty string - abort.\n";
    return;
  }
  my $citations = $c->citations($uri, $get);
  show_err_and_warn($c);
  unless ($citations) {
    print "No citations.\n\n";
    return;
  }
  my $result = $citations->fetch;
  show_citation($result);
  #my $unwritten = Bibliotech::Unwritten::Citation->from_citationsource_result($result, 0, $plugin, $understands_code);
  #warn Dumper($unwritten);
  #my $citation = $unwritten->write;
  #warn Dumper($citation);
}

sub show_citation {
  my $result = shift;
  print "Data:\n";
  my $id = $result->identifiers;
  if (defined $id and %{$id}) {
    # show all identifiers but show the three main ones in canonical order with canonical labels
    foreach (grep { $id->{$_->[0]} } (['doi', 'DOI'], ['pubmed', 'PMID'], ['asin', 'ASIN'])) {
      my ($key, $label) = @{$_};
      print '  ', $label, ': ', $id->{$key}||'', "\n";
    }
    foreach (map { [$_, $_] } grep { !/^(doi|pubmed|asin)$/ } keys %{$id}) {
      my ($key, $label) = @{$_};
      print '  ', $label, ' (non-standard): ', $id->{$key}||'', "\n";
    }
  }
  print '  Title: ',    $result->title||'', "\n";
  print '  Journal: ',  (defined $result->journal ? $result->journal->name||'' : ''), "\n";
  print '  Volume: ',   $result->volume||'', "\n";
  print '  Issue: ',    $result->issue||'', "\n";
  print '  Page: ',     $result->page||'', "\n";
  print '  Date: ',     $result->date||'', "\n";
  if (my $authors = $result->authors) {
    my @author_str;
    $authors->foreach(sub{ push @author_str, extract_name($_); });
    print '  Authors (', scalar @author_str, '): ', join(', ', @author_str), "\n";
  }
  else {
    print "  No Authors", "\n";
  }
  print "\n";
}

sub extract_name {
  my $author = shift;
  my $get = sub { my $field = shift;
		  return unless $author->can($field) or $author->can('AUTOLOAD');
		  return $author->$field; };
  my $or  = sub { foreach (@_) { my $value = $get->($_);
				 return $value if defined $value; }
		  return; };
  return join(' ', grep { $_ } ($or->('forename', 'firstname'), $or->('surname', 'lastname')));
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

sub scan_uri {
  my ($uri, $b, $get) = @_;
  my $module = Bibliotech::Plugin::CitationSource->scan($uri, [$b], [$get]) or die 'no citation source object (scan)';
  print 'Scan returns ', ref($module), " as winner.\n";
  return $module;
}
