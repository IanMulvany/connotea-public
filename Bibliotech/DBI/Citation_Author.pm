package Bibliotech::Citation_Author;
use strict;
use base 'Bibliotech::DBI';

__PACKAGE__->table('citation_author');
__PACKAGE__->columns(Primary => qw/citation_author_id/);
__PACKAGE__->columns(Essential => qw/citation author displayorder/);
__PACKAGE__->columns(Others => qw/created/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->has_a(citation => 'Bibliotech::Citation');
__PACKAGE__->has_a(author => 'Bibliotech::Author');

sub my_alias {
  'cta';
}

1;
__END__
