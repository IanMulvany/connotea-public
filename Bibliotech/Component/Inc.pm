# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::Inc class provides the mechanism for include
# files to be called from templates.

package Bibliotech::Component::Inc;
use strict;
use base 'Bibliotech::Component';
use IO::File;

sub last_updated_basis {
  shift->operative_filename;
}

sub filename {
  my ($self, $r) = @_;
  die 'must pass in Apache::RequestRec or Apache2::RequestRec object'
      unless UNIVERSAL::isa($r, 'Apache::RequestRec') || UNIVERSAL::isa($r, 'Apache2::RequestRec');
  my $base = $r->filename.$r->path_info;
  $base .= '.inc' unless $base =~ /\.\w{1,8}$/;
  return $base;
}

sub check_filename {
  my ($self, $r, $not_found_value, $forbidden_value, $ok_value) = @_;
  my $filename = $self->filename($r);
  return $not_found_value unless -e $filename;
  return $forbidden_value unless -r $filename;
  return $ok_value;
}

sub option_filename {
  my ($self, $filename) = @_;
  if ($filename =~ m|^//|) {
    $filename =~ s|^//|/|;
  }
  elsif ($filename =~ m|^/|) {
    $filename =~ s|^/||;
    $filename = $self->bibliotech->docroot.$filename.'.inc';
  }
  else {
    my $r = $self->bibliotech->request;
    (my $path = $r->filename.$r->path_info) =~ s|/([^/]*)$|/${filename}.inc|;
    $filename = $path;
  }
  return $filename;
}

sub operative_filename {
  my $self     = shift;
  my $options  = $self->options || {};
  my $filename = $options->{filename} ? $self->option_filename($options->{filename})
                                      : $self->filename($self->bibliotech->request);
  return $filename;
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $bibliotech = $self->bibliotech;
  my $user       = $bibliotech->user;
  my $user_id    = $user ? $user->user_id : undef;
  my $filename   = $self->operative_filename;

  my $cached = $self->memcache_check(class  => __PACKAGE__,
				     method => 'html_content',
				     user   => $user_id || 'visitor',
				     id     => $filename);
  return $cached if defined $cached;

  my $options = $self->options || {};
  my $doc;
  my $fh = IO::File->new($filename) or return Bibliotech::Page::HTML_Content->blank;
  { local $/ = undef; $doc = <$fh>; }
  $fh->close;

  my $inc;
  if ($doc =~ /\[\% /) {
    my $docroot = $bibliotech->docroot;
    $filename =~ s|^\Q$docroot\E||;
    $inc = $self->tt($filename);
  }
  else {
    $inc = $bibliotech->replace_text_variables([$doc], $user,
					       $options->{variables}, $options->{variables_code_obj})->[0];
  }

  $self->discover_main_title($inc);

  return $self->memcache_save(Bibliotech::Page::HTML_Content->simple($inc));
}

1;
__END__
