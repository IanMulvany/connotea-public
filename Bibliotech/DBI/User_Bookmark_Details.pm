package Bibliotech::User_Bookmark_Details;
use strict;
use base 'Bibliotech::DBI';

__PACKAGE__->table('user_bookmark_details');
__PACKAGE__->columns(Primary => qw/user_bookmark_id/);
__PACKAGE__->columns(Essential => qw/title description/);
__PACKAGE__->force_utf8_columns(qw/title description/);

use overload
    bool => sub { UNIVERSAL::isa(shift, 'Bibliotech::User_Bookmark_Details'); },
    fallback => 1;

sub my_alias {
  'ubd';
}

1;
__END__
