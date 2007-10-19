# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::Footer class provides a footer.

package Bibliotech::Component::Footer;
use strict;
use base 'Bibliotech::Component';
use Bibliotech::DBI;
use Bibliotech::FilterNames;
use Bibliotech::Profile;

our %COUNT_CALLS;

BEGIN {
  foreach my $table (qw/article bookmark tag user user_article/) {
    my $class = Bibliotech::DBI->class_for_table($table);
    $COUNT_CALLS{'count_all_'.$table} = sub { $class->count_all };
    $COUNT_CALLS{'count_active_'.$table} = sub { $class->count_active };
  }
}

sub last_updated_basis {
  ('DBI', shift->include_basis('/footer'));
}

sub lazy_update {
  180;
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $cached = $self->memcache_check(class => __PACKAGE__);
  return $cached if defined $cached;

  my $doc = $self->include('/footer', 'footer', $verbose, $main, \%COUNT_CALLS) 
      || 'Database active with '.$COUNT_CALLS{count_active_bookmark}->().' active bookmarks.';

  return $self->memcache_save(Bibliotech::Page::HTML_Content->simple($doc));
}

1;
__END__
