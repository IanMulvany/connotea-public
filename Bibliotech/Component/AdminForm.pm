# Copyright 2007 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::AdminForm class provides an
# interface to administrative tasks.

package Bibliotech::Component::AdminForm;
use strict;
use base 'Bibliotech::Component';
use Bibliotech::DBI::Set;
use List::Util qw/sum/;
use Data::Dumper;

our $ADMIN_USERS = __PACKAGE__->cfg('ADMIN_USERS');
$ADMIN_USERS = [$ADMIN_USERS] unless ref $ADMIN_USERS;

sub last_updated_basis {
  'NOW';
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;
  my $user       = $self->getlogin or return $self->saylogin('to access the admin menu');
  my $username   = $user->username;
  grep { $username eq $_ } @{$ADMIN_USERS} or return Bibliotech::Page::HTML_Content->simple('Not an admin.');
  my $bibliotech = $self->bibliotech;
  my $cgi        = $bibliotech->cgi;
  my $results    = ($cgi->param('button') eq 'search' ? $self->results($cgi) : undef);
  my $o          = $self->tt('compadmin', $self->vars($results), undef);
  return Bibliotech::Page::HTML_Content->simple($o);
}

sub vars {
  my ($self, $results) = @_;
  {results => $results,
   do {
     my $ua_counts;
     my $get_ua_counts = sub {
       return @{$ua_counts} if defined $ua_counts;
       return @{$ua_counts = []} unless defined $results;
       return @{$ua_counts = [map { $_->count_user_articles } @{$results}]};
     };
     (total_user_articles   => sub { sum    ($get_ua_counts->()) },
      average_user_articles => sub { average($get_ua_counts->()) },
      median_user_articles  => sub { median ($get_ua_counts->()) },
     );
   },
   do {
     my $user_count;
     my $get_user_count = sub {
       return $user_count if defined $user_count;
       return $user_count = 0 unless defined $results;
       return $user_count = $results->count;
     };
     my $active_user_count;
     my $get_active_user_count = sub {
       return $active_user_count if defined $active_user_count;
       return $active_user_count = 0 unless defined $results;
       return $active_user_count = grep { $_->active } @{$results};
     };
     (total_user_count    => sub { $get_user_count->() },
      active_user_count   => sub { $get_active_user_count->() },
      inactive_user_count => sub { $get_user_count->() - $get_active_user_count->() },
     );
   },
  };
}

sub chop_point_zero {
  local $_ = shift;
  s/\.0$//;
  return $_;
}

sub average {
  return 0 unless @_;
  return chop_point_zero(sprintf('%0.1f', sum(@_)/scalar(@_)));
}

sub median {
  return 0 unless @_;
  return $_[0] if @_ == 1;
  my @vals = sort @_;
  my $halfway = $#vals / 2;
  return $vals[$halfway] unless $#vals % 2;
  return average($vals[$halfway-0.5], $vals[$halfway+0.5]);
}

sub results {
  my ($self, $cgi) = @_;
  my $sth = $self->sth_for_results(sub { $self->cleanparam($cgi->param(shift)) }) or return Bibliotech::DBI::Set->new;
  return Bibliotech::DBI::Set->new(map { Bibliotech::User->construct($_) } $sth->fetchall_hash);
}

my %TYPE2OP = ('' => '=', 'eq' => '=',
	       'lt' => '<', 'le' => '<=', 'gt' => '>', 'ge' => '>=',
	       'like' => 'LIKE', 'rlike' => 'RLIKE');

sub sth_for_results {
  my ($self, $getparam) = @_;

  my @where_criteria;
  my @having_criteria;
  my @where_values;
  my @having_values;

  my $add_criteria = sub {
    my ($is_having, $where, @values) = @_;
    if ($is_having) {
      push @having_criteria, $where;
      push @having_values, @values;
    }
    else {
      push @where_criteria, $where;
      push @where_values, @values;
    }
  };

  my $normal = sub {
    my ($key, $field, $is_having) = @_;
    my $value = $getparam->($key);
    if (defined $value && length $value) {
      my $op = $TYPE2OP{$getparam->('type'.$key)||''};
      $add_criteria->($is_having,
		      join(' ', $field || 'u.'.$key, $op, '?'),
		      $op eq 'LIKE' ? '%'.$value.'%' : $value);
    }
  };

  my $between = sub {
    my ($key, $field, $key2, $is_having) = @_;
    my $key1 = ($key2 ? $key : $key.'1');
    $key2 .= $key.'2';
    my $value1 = $getparam->($key1);
    if (defined $value1 && length $value1) {
      my $value2 = $getparam->($key2);
      $value2 = $value1 unless defined $value2 && length $value2;
      $add_criteria->($is_having,
		      join(' ', $field || 'u.'.$key, 'BETWEEN ? AND ?'),
		      $value1.' 00:00:00', $value2.' 23:59:59');
    }
  };

  $normal->($_) foreach (qw/user_id username email lastname firstname active/);
  $normal->('articles', 'user_articles_count_packed', 'having');
  $normal->('group', 'g.name');
  $between->('created');

  return unless @where_criteria or @having_criteria;
  my $sth = Bibliotech::User->sql_by_admin((@where_criteria  ? 'WHERE '. join(' AND ', @where_criteria)  : ''),
					   (@having_criteria ? 'HAVING '.join(' AND ', @having_criteria) : ''))
      or die 'cannot get sql_by_admin';
  $sth->execute(@where_values, @having_values) or die $sth->errstr;
  return $sth;
}

1;
__END__
