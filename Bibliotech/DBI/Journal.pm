package Bibliotech::Journal;
use strict;
use base 'Bibliotech::DBI';

__PACKAGE__->table('journal');
__PACKAGE__->columns(Primary => qw/journal_id/);
__PACKAGE__->columns(Essential => qw/name issn coden country medline_code medline_ta nlm_unique_id/);
__PACKAGE__->columns(Others => qw/created/);
__PACKAGE__->force_utf8_columns(qw/name/);
__PACKAGE__->datetime_column('created', 'before_create');

sub my_alias {
  'j';
}

sub unique {
  'issn';
}

sub clean_whitespace_all {
  my $self = shift;
  $self->SUPER::clean_whitespace($_) foreach (qw/name issn coden country medline_code medline_ta nlm_unique_id/);
}

sub json_content {
  my $self = shift;
  my $hash = $self->SUPER::json_content;
  $hash->{name} ||= $hash->{medline_ta};
  delete $hash->{medline_ta};
  return $hash;
}

1;
__END__
