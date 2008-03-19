# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This file provides plugin scanning.

package Bibliotech::Plugin;
use strict;
use Storable qw(dclone);
use List::Util qw(reduce);
use List::MoreUtils qw(all);

our $errstr;

sub new {
  my $class = shift;
  return bless {}, ref $class || $class;
}

sub noun {
  'item';
}

sub normalize {
  undef;
}

sub modules {
  ();
}

sub min_api_version {
  1.0;
}

sub instance {
  my ($self, $class, $obj_new_params) = @_;
  my @obj_new_params = @{$obj_new_params || []};
  my ($obj, $api_version);
  eval {
    $obj = $class->new(@obj_new_params) or die "cannot create new $class object";
    $api_version = $obj->api_version;
  };
  die "Error setting up $class module: $@" if $@;
  die "API too old: $api_version\n" unless $api_version >= $self->min_api_version;
  return $obj;
}

sub _item_copy {
  local $_ = shift;
  return ref $_ ? dclone($_) : $_;
}

sub scan {
  my ($self, $item, $obj_new_params, $obj_call_params) = @_;

  die 'must provide a '.$self->noun unless $item;

  my $newitem = $self->normalize($item);
  $item = $newitem if defined $newitem;

  my @modules = $self->modules or return undef;

  # the various eval's below are not so much to accomplish any programatic feat, but just to encapsulate
  # calls into the citation modules so that error messages from die's inside those modules can be prepended
  # with context information from this subroutine

  # select the best citation source module
  my $best_mod;
  eval {
    my @mods;
    foreach my $class (@modules) {
      my $obj;
      eval {
	$obj = $self->instance($class, $obj_new_params);
      };
      if ($@) {
	next if $@ =~ /^API too old/;
	die $@;
      }
      if (@mods) {
	if ($obj->can('potential_understands')) {
	  my $potential_score = eval { $obj->potential_understands };
	  die 'Error from '.ref($obj)."::potential_understands: $@" if $@;
	  next unless all { $potential_score > $_ } (map { $_->[0] } @mods);  # because we won't beat one that we have
	}
      }
      my $score = eval { $obj->understands(_item_copy($item), @{$obj_call_params||[]}); };
      die 'Error from '.ref($obj)."::understands(\'$item\'): $@" if $@;
      warn "Bibliotech::Plugin::scan - $class = $score\n";
      next if !$score or $score <= 0;  # because that means does not understand or transient error
      push @mods, [$score => $obj];
      last if $score == 1;  # because it will win anyway
    }
    $best_mod = reduce { $a->[0] < $b->[0] ? $a : $b } @mods if @mods;
  };
  die "error in plugin scan loop: $@" if $@;
  return unless $best_mod;
  my ($score, $mod) = @{$best_mod};
  return ($mod, $score) if wantarray;  # object, "understands" score
  return $mod;                         # object
}

# return a hash suitable for use in CGI forms
sub selection {
  my $self = shift;
  my @modules;
  my %modules;
  foreach my $class ($self->modules) {
    (my $shortclass = $class) =~ s/^.*:://;
    push @modules, $shortclass;
    my $name;
    eval {
      $name = $class->can('selection_name') ? $class->selection_name : $class->name;
    };
    die "could not get name from module $class: $@" if $@;
    $modules{$shortclass} = $name;
  }
  return wantarray ? (\@modules, \%modules) : \%modules;
}

# return a list suitable for use in TT templates
sub selection_tt {
  my ($modules_list, $modules_hash) = shift->selection;
  return Bibliotech::Plugin::FoundList->new(map { Bibliotech::Plugin::Found->new({shortclass => $_, name => $modules_hash->{$_}}) } @{$modules_list});
}


package Bibliotech::Plugin::FoundList;

sub new {
  my $class = shift;
  bless [@_], $class;
}

sub as_list {
  my $self = shift;
  return $self;
}


package Bibliotech::Plugin::Found;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/shortclass name/);


package Bibliotech::Plugin::CitationSource;
use strict;
use base 'Bibliotech::Plugin';
use Bibliotech::Config;
use URI;

our $CITATION_MODULES = Bibliotech::Config->get('CITATION_MODULES') || [];
die 'CITATION_MODULES must be an array' unless ref $CITATION_MODULES eq 'ARRAY';
our @MODULES = map('Bibliotech::CitationSource::'.$_, @{$CITATION_MODULES});
for (@MODULES) { eval "use $_"; if ($@) { $Bibliotech::Plugin::errstr = $@; die $@; } }

sub noun {
  'URI';
}

sub normalize {
  my ($self, $uri) = @_;
  return UNIVERSAL::isa($uri, 'URI') ? $uri : new URI ($uri);
}

sub modules {
  @MODULES;
}


package Bibliotech::Plugin::Import;
use strict;
use base 'Bibliotech::Plugin';
use Bibliotech::Config;

our $IMPORT_MODULES = Bibliotech::Config->get('IMPORT_MODULES') || [];
die 'IMPORT_MODULES must be an array' unless ref $IMPORT_MODULES eq 'ARRAY';
our @MODULES = map('Bibliotech::Import::'.$_, @{$IMPORT_MODULES});
for (@MODULES) { eval "use $_"; if ($@) { $Bibliotech::Plugin::errstr = $@; die $@; } }

sub noun {
  'document';
}

sub modules {
  @MODULES;
}


package Bibliotech::Plugin::Proxy;
use strict;
use base 'Bibliotech::Plugin';
use Bibliotech::Config;
use URI;

our $PROXY_MODULES = Bibliotech::Config->get('PROXY_MODULES') || [];
die 'PROXY_MODULES must be an array' unless ref $PROXY_MODULES eq 'ARRAY';
our @MODULES = map('Bibliotech::Proxy::'.$_, @{$PROXY_MODULES});
for (@MODULES) { eval "use $_"; if ($@) { $Bibliotech::Plugin::errstr = $@; die $@; } }

sub noun {
  'URI';
}

sub normalize {
  my ($self, $uri) = @_;
  return UNIVERSAL::isa($uri, 'URI') ? $uri : new URI ($uri);
}

sub modules {
  @MODULES;
}


1;
__END__
