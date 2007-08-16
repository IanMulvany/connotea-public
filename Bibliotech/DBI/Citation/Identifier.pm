package Bibliotech::Citation::Identifier;
use strict;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/source type infotype noun xmlnoun prefix value suffix urilabel uri natural_fmt/);

sub as_string {
  my $self = shift;
  return join('', $self->prefix || '', $self->value || '', $self->suffix || '');
}

sub info_uri {
  my $self = shift;
  return URI->new(join('', 'info:', $self->infotype || $self->type, '/', $self->value));
}

sub info_or_link_uri {
  my $self = shift;
  return $self->info_uri if $self->value;
  return $self->uri;
}

sub info_or_link_text {
  my $self = shift;
  return $self->info_uri->as_string if $self->value;
  return $self->link_text;
}

sub format {
  my ($self, $fmt) = @_;
  my $str = $fmt;
  $str =~ s/\%s/$self->source/eg;
  $str =~ s/\%t/$self->type/eg;
  $str =~ s/\%i/$self->infotype/eg;
  $str =~ s/\%n/$self->noun/eg;
  $str =~ s/\%</$self->prefix/eg;
  $str =~ s/\%v/$self->value/eg;
  $str =~ s/\%>/$self->suffix/eg;
  $str =~ s/\%L/$self->urilabel/eg;
  $str =~ s/\%U/$self->uri/eg;
  return $str;
}

sub natural_uri {
  my $self = shift;
  return $self->format($self->natural_fmt);
}

sub link_text {
  my $self = shift;
  return ($self->prefix || '').($self->value || '') || $self->noun || 'link';
}

1;
__END__
