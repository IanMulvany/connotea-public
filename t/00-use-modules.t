#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Find;

test_dir('.', \@ARGV);

sub test_dir {
  my $dir      = shift || '.';
  my $excludes = shift || [];
  my @pmlist;
  find(sub { keep_if_filename_pm(\@pmlist) }, $dir);
  my @uselist = grep { is_checkable_module($_) && !is_excluded($_, $excludes) } map { filename_to_module($_) } @pmlist;
  plan tests => scalar(@uselist);
  eval "use lib \'$dir\';";
  foreach my $module (@uselist) {
    use_ok($module);
  }
}

sub keep_if_filename_pm {
  my ($dirname, $filename, $list) = ($File::Find::dir, $File::Find::name, @_);
  push @{$list}, $filename if !is_repo_dir($dirname) && is_filename_pm($filename);
}

sub is_repo_dir {
  shift =~ /(?:_darcs|contributed_plugins)/;
}

sub is_filename_pm {
  shift =~ /\.pm$/o;
}

sub filename_to_module {
  local $_ = shift;
  s|^\./||;
  s|\.pm$||;
  s|/|::|g;
  return $_;
}

sub is_checkable_module {
  my $module = shift;
  return !is_apache_dependent_module($module) && !is_unfinished_module($module);
}

sub is_apache_dependent_module {
  shift =~ /^Bibliotech::(?:ApacheProper|Apache|ApacheInit|AuthCookie|Component::(?:LoginForm|LogoutForm|RegisterForm|VerifyForm|ForgotPasswordForm)|WebCite|Clicks)$/o;
}

sub is_unfinished_module {
  shift =~ /^Bibliotech::Import::BibTeX$/o;
}

sub is_excluded {
  my ($module, $excludes_ref) = @_;
  return grep { $module eq $_ } @{$excludes_ref};
}
