# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This file provides an object-friendly version of Set::Array

package Bibliotech::DBI::Set;
use strict;
use base 'Set::Array';
use Want;

# make count return how many entries there are
sub count {
  shift->length;
}

sub flatten_helper {
  my @ret;
  foreach (@_) {
    push @ret, (ref($_) eq 'ARRAY' ? flatten_helper(@{$_}) : $_);
  }
  return @ret;
}

# object-friendly
sub flatten{
   my($self) = @_;

   if( want('OBJECT') ){
     return $self->new(flatten_helper(@{$self}));
   }
   if( !defined wantarray ){
     @{$self} = flatten_helper(@{$self});
      return $self
   }

   my @temp = flatten_helper(@{$self});
   if(wantarray){ return @temp }
   if(defined wantarray){ return \@temp }
}

# object-friendly, plus preserve order
sub unique {
  my ($set) = @_;

  my $new_set = ref($set)->new;
  my %seen;
  foreach (@{$set}) {
    CORE::push(@{$new_set}, $_)  # preserving order
	unless $seen{$_}++;
  }

  if (want('OBJECT')) {
    return $new_set;
  }
  if ( !(defined wantarray) ) {
    @{$set} = @{$new_set};
    return $set;
  }

  return @{$new_set} if wantarray;
  return $new_set;
}

# object-friendly
sub difference{
   my($op1, $op2, $reversed) = @_;
   ($op2,$op1) = ($op1,$op2) if $reversed;

   my(%item1,%item2,@diff);
   CORE::foreach(@$op2){ $item2{$_}++ }

   CORE::foreach(@$op1){
     next if $item1{$_}++;
     next if $item2{$_};
     CORE::push(@diff,$_);
   }
	
   if(want('OBJECT') || !(defined wantarray)){
      @$op1 = @diff;
      return $op1;
   }

   if(wantarray){ return @diff }
   if(defined wantarray){ return \@diff }
}

# intersection() is already object-friendly

# object-friendly
sub symmetric_difference{
   my($op1, $op2, $reversed) = @_;
   ($op2,$op1) = ($op1,$op2) if $reversed;

   my(%count1,%count2,%count3,@symdiff);
   @count1{@$op1} = @$op1;
   @count2{@$op2} = @$op2;

   CORE::foreach(CORE::keys %count1){
     $count3{$_} ||= [];
     my $c = $count3{$_};
     $c->[0]++;
     $c->[1] = $count1{$_};
   }
   CORE::foreach(CORE::keys %count2){
     $count3{$_} ||= [];
     my $c = $count3{$_};
     $c->[0]++;
     $c->[1] = $count2{$_};
   }

   if(want('OBJECT') || !(defined wantarray)){
      @$op1 = CORE::map{$count3{$_}->[1]} CORE::grep{$count3{$_}->[0] == 1} CORE::keys %count3;
      return $op1;
   }

   @symdiff = CORE::map{$count3{$_}->[1]} CORE::grep{$count3{$_}->[0] == 1} CORE::keys %count3;
   if(wantarray){ return @symdiff }
   if(defined wantarray){ return \@symdiff }
}

# object-friendly
sub union{
   my($op1, $op2, $reversed) = @_;
   ($op2,$op1) = ($op1,$op2) if $reversed;

   my %union;
   CORE::foreach(@$op1, @$op2){
     $union{$_} ||= [];
     my $u = $union{$_};
     $u->[0]++;
     $u->[1] = $_;
   }

   if(want('OBJECT') || !(defined wantarray)){
      @$op1 = CORE::map{$union{$_}->[1]} CORE::keys %union;
      return $op1;
   }

   my @union = CORE::map{$union{$_}->[1]} CORE::keys %union;

   if(wantarray){ return @union }
   if(defined wantarray){ return \@union }
}

sub first {
  shift->shift;  # ;-)
}

sub next {
  shift->shift;  # ;-)
}

sub output_line {
  my ($self, $func, $prefix) = @_;
  return $prefix || '', join(', ', map($_->$func, @$self)), "\n";
}

# support Bibliotech::DBI::Set object being used in FOREACH directive of Template Toolkit
# as it is within Bibliotech::WebAPI::Action::Tags::Get for answer->list
sub as_list {
  # simply by having as_list() defined, Template::Iterator now interprets this differently, as an arrayref
  shift;
}

package Bibliotech::DBI::Set::Line;
use strict;

use overload
    '""' => sub { shift->stringify_self; },
    bool => sub { shift->stringify_self ? 1 : 0; },
    fallback => 1;

sub stringify_self {
  shift->[0];
}

1;
__END__
