#!/usr/bin/perl
use strict;
use Bibliotech::DBI;

# run after database has been altered to create new tables but while site is still paused

my $dbh = Bibliotech::DBI->db_Main();

check_for_upgraded_tables();
print localtime()."\n";
reassign_related_bookmarks();
print localtime()."\n";
delete_transient_articles();
print localtime()."\n";
reconcat_multi_articles();
print localtime()."\n";

sub check_for_upgraded_tables {
  my $tables = $dbh->selectcol_arrayref('show tables');
  my $found = grep { $_ eq 'article' } @{$tables};
  die "article table does not exit, bailing\n" unless $found;
}

sub reassign_related_bookmarks {
  foreach my $id ('pubmed', 'doi', 'asin') {
    my $sth = $dbh->prepare(make_research_sql($id));
    $sth->execute;
    handle_id_sth($id, $sth);
  }
}

sub delete_transient_articles_sql {
  'delete from article where (select count(*) from bookmark where article = article_id) = 0 and (select count(*) from user_article where article = article_id) = 0';
}

sub delete_transient_articles {
  print "deleting transient article rows...\n";
  $dbh->do(delete_transient_articles_sql());
}

sub reconcat_multi_articles_sql {
  'select a.article_id, count(b.bookmark_id) from article a left join bookmark b on (b.article = a.article_id) group by a.article_id having count(b.bookmark_id) > 1';
}

sub reconcat_multi_articles {
  my $sth = $dbh->prepare(reconcat_multi_articles_sql());
  $sth->execute;
  while (my ($multi_article) = $sth->fetchrow_array) {
    print "reconcat $multi_article\n";
    my $article = Bibliotech::Article->retrieve($multi_article);
    eval { $article->reconcat_citations; };
    warn $@ if $@;  # do not terminate, because these will probably be isolated problems
  }
}

sub article_for_bookmark {
  my $ref = $dbh->selectcol_arrayref('select article from bookmark where bookmark_id = ?', undef, shift);
  return $ref->[0];
}

sub count_bookmarks_for_article {
  my $ref = $dbh->selectcol_arrayref('select count(*) from bookmark where article = ?', undef, shift);
  return $ref->[0];
}

sub switch_bookmarks_to_article {
  my ($other_article, $article) = @_;
  return if $article == $other_article;
  $dbh->do('update bookmark set article = ? where article = ?', undef, $article, $other_article);
}

sub make_research_sql {
  my ($id) = @_;
  return "select $id, count($id), group_concat(bookmark_id) from bookmark b inner join citation c on (b.citation=c.citation_id) where $id is not null and $id != \'\' group by $id having count($id) > 1";
}

sub handle_id_sth {
  my ($id, $sth) = @_;
  while (my ($idval, $count, $bookmarklist) = $sth->fetchrow_array) {
    print "$id $idval $count\n";
    my @bookmarks = split(/,/, $bookmarklist);
    my $first     = shift @bookmarks;
    my $article   = article_for_bookmark($first);
    switch_bookmarks_to_article(article_for_bookmark($_) => $article) foreach (@bookmarks);
  }
}
