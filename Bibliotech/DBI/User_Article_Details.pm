package Bibliotech::User_Article_Details;
use strict;
use base 'Bibliotech::DBI';

__PACKAGE__->table('user_article_details');
__PACKAGE__->columns(Primary => qw/user_article_id/);
__PACKAGE__->columns(Essential => qw/title description/);
__PACKAGE__->force_utf8_columns(qw/title description/);

use overload
    bool => sub { UNIVERSAL::isa(shift, 'Bibliotech::User_Article_Details'); },
    fallback => 1;

sub my_alias {
  'uad';
}

1;
__END__
