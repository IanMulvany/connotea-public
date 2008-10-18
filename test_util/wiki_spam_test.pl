#!/usr/bin/perl
use warnings;
use strict;
use Bibliotech::Component::Wiki;
print "Enter wiki text:\n";
Bibliotech::Component::Wiki::_validate_submitted_content(do { local $/ = undef; <>; }, 1);
print "OK.\n";
