#!/usr/bin/perl

use strict;
use warnings;

while(my $file = shift @ARGV) {
    open FILE, $file;
    my $content = join('', <FILE>);
    close FILE;
    $content =~ s!\n!\n<br />\n!g;
    $content =~ s!'(http:.*?)'!<a href="$1">$1</a>!ig;
    $file =~ s!\.txt!.html!;
    open OUT, ">$file";
    print OUT "<html>\n<body>\n$content\n</body></html>\n";
    close OUT;
}

