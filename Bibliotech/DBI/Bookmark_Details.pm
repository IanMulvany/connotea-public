package Bibliotech::Bookmark_Details;
use strict;
use base 'Bibliotech::DBI';

__PACKAGE__->table('bookmark_details');
__PACKAGE__->columns(Primary => qw/bookmark_id/);
__PACKAGE__->columns(Essential => qw/title created/);
__PACKAGE__->force_utf8_columns(qw/title/);
__PACKAGE__->datetime_column('created', 'before_create');

use overload
    bool => sub { UNIVERSAL::isa(shift, 'Bibliotech::Bookmark_Details'); },
    fallback => 1;

sub my_alias {
  'bd';
}

1;
__END__
