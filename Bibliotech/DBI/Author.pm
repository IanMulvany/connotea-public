package Bibliotech::Author;
use strict;
use base 'Bibliotech::DBI';

__PACKAGE__->table('author');
#__PACKAGE__->columns(All => qw/author_id firstname forename initials middlename lastname suffix postal_address affiliation email user created/);
__PACKAGE__->columns(Primary => qw/author_id/);
__PACKAGE__->columns(Essential => qw/firstname forename initials middlename lastname suffix misc postal_address affiliation email user/);
__PACKAGE__->columns(Others => qw/created/);
__PACKAGE__->force_utf8_columns(qw/firstname forename initials middlename lastname suffix postal_address affiliation/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->has_many(citations => ['Bibliotech::Citation_Author' => 'citation']);
__PACKAGE__->has_a(user => 'Bibliotech::User');

sub my_alias {
  'a';
}

sub clean_whitespace_all {
  my $self = shift;
  $self->clean_whitespace($_) foreach (qw/firstname forename initials middlename lastname suffix misc postal_address affiliation/);
}

sub name {
  shift->collective_name(@_);
}

1;
__END__
