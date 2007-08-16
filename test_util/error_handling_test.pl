#!/usr/bin/perl

use strict;
use warnings;

use lib '..';
use Bibliotech::Fake;
use Bibliotech::Util;
use URI;
use Data::Dumper;

use constant USAGE => "\nusage: perl error_handling_test.pl <plugin> <dataset>\n\twhere <plugin> ex. Pubmed, DOI...\n\twhere <dataset> contains ex. [0-3](space)URL\n";

my $plugin = shift @ARGV;
die ("No plug-in specified, so I can't do anything\n" . USAGE) unless $plugin;

my $dataset = shift @ARGV;
die ("No file specified, so I can't do anything\n" . USAGE) unless $dataset;

$plugin = 'Bibliotech::CitationSource::'.$plugin;
eval "use $plugin";

#
# Load dataset in where dataset is a simple file that contains expected error level and url, separated by a space
#	ex. (where 0 - is a 'good' url; 2 - is a url with an error)
#		0 http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Retrieve&db=pubmed&dopt=Abstract&list_uids=11417053
#		2 http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Retrieve&db=pubmed&dopt=Abstract&list_uids==16865696
#
my(@urls);
&loadDataSet(\@urls, $dataset);

&hints;

die $@ if $@;

my $b = Bibliotech::Fake->new;
my $c = $plugin->new($b);

foreach my $t (@urls)
{
    my $uri = URI->new($t->{URL});
    my $cache;
    my $get = sub { return Bibliotech::Util::get($uri, $b, \$cache) };
    print "Testing: \'$uri\'\n";
    print "Level Expected: $t->{ERRLEV}\n";

		#
		# clear out errstr and warnstr between each url
		#
		$c->errstr("");
		$c->warnstr("");

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
			print "Authors: ";
			$result->authors->foreach(sub{ print $_->forename.' '.$_->lastname.', '; });
			print "\n";
    }
    else {
			print "No Authors", "\n";
    }
    print "\n";
    sleep 3;
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

sub loadDataSet {
	my ($urls, $dataset) = @_;

	open (FILE, $dataset) or die $!;

	while(<FILE>) {
		chomp;
		my @line = split(/ /);

		die "incorrect data format, try [0-3](space)URL\n" unless $line[1];

		push(@$urls, {ERRLEV=>$line[0], URL=>$line[1]});
	}

	#print "URLS " . Dumper($urls);

	close (FILE) or die $!;
}

sub hints {
	print "Error Handling Levels and Behaviors\n";
	print "\tLevel 0 Good - will return metadata\n";
	print "\tLevel 1 Silent - Warning from module, returns undef\n";
	print "\t\tEx. network error, bad url...\n";
	print "\tLevel 2 Potential Bugs - Error from module, returns undef\n";
	print "\t\tEx. parsing error, perl error...\n";
	print "\tLevel 3 To User - Error from module, dies\n";
	print "\t\tEx. no doi...\n";
}
