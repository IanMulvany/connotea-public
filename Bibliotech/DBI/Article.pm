package Bibliotech::Article;
use strict;
use base 'Bibliotech::DBI';

__PACKAGE__->table('article');
__PACKAGE__->columns(Primary => qw/article_id/);
__PACKAGE__->columns(Essential => qw/hash/);
__PACKAGE__->columns(Others => qw/created updated/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->datetime_column('updated', 'before_update');
__PACKAGE__->has_many(bookmarks => ['Bibliotech::Bookmark' => 'article']);

1;
__END__
