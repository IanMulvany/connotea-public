#!/usr/bin/perl
use strict;
use Bibliotech::DBI;

# run after database has been altered to create new tables but while
# site is still paused

# this script is destructive of data: user citations on multiple
# bookmarks that become the same article, only one posting is kept

my $dbh = Bibliotech::DBI->db_Main();
print 'Start: '.localtime()."\n";
main();
print 'End: '.localtime()."\n";

sub main {
  check_for_upgraded_tables();
  reassign_related_bookmarks();
  delete_transient_articles();
  delete_orphaned_tags();
  delete_orphaned_comments();
  reconcat_multi_articles();
}

sub check_for_upgraded_tables {
  my $tables = $dbh->selectcol_arrayref('show tables');
  my $found = grep { $_ eq 'article' } @{$tables};
  die "article table does not exit, bailing\n" unless $found;
}

sub reassign_related_bookmarks_sql {
  my $id = shift;
  return "select $id, count($id), group_concat(bookmark_id) from bookmark b inner join citation c on (b.citation=c.citation_id) where $id is not null and $id != \'\' group by $id having count($id) > 1";
}

sub reassign_related_bookmarks {
  foreach my $id ('pubmed', 'doi', 'asin') {
    my $sth = $dbh->prepare(reassign_related_bookmarks_sql($id));
    $sth->execute;
    while (my ($idval, undef, $bookmarklist) = $sth->fetchrow_array) {
      reassign_related_bookmarks_one($id, $idval, split(/,/, $bookmarklist));
    }
  }
}

sub article_for_bookmark {
  my $ref = $dbh->selectcol_arrayref('select article from bookmark where bookmark_id = ?', undef, shift);
  return $ref->[0];
}

sub reassign_related_bookmarks_one {
  my ($id, $idval, @bookmarks) = @_;
  print "$id $idval ".scalar(@bookmarks)."\n";
  my $first   = shift @bookmarks;
  my $article = article_for_bookmark($first);
  switch_over_articles(article_for_bookmark($_) => $article) foreach (@bookmarks);
}

sub switch_over_articles {
  my ($old_article_id, $new_article_id) = @_;
  return if $new_article_id == $old_article_id;
  switch_bookmarks_to_article($old_article_id, $new_article_id);
  switch_user_articles_to_article($old_article_id, $new_article_id);
}

sub switch_bookmarks_to_article {
  my ($old_article_id, $new_article_id) = @_;
  $dbh->do('update bookmark set article = ? where article = ?', undef, $new_article_id, $old_article_id);
}

# this is the same thing for user_article, but here we have to take
# care because it is possible that we need to reassign more than one
# user_article for the same user to the same article which is not
# allowed; the solution is to update one and delete the rest
sub switch_user_articles_to_article {
  my ($old_article_id, $new_article_id) = @_;
  my $sth = $dbh->prepare('select user_article_id, user, citation from user_article where article = ?');
  $sth->execute($old_article_id);
  my $check_user_article_dup = $dbh->prepare('select user_article_id from user_article where user = ? and article = ?');
  while (my ($user_article_id, $user_id, $citation_id) = $sth->fetchrow_array) {
    $check_user_article_dup->execute($user_id, $new_article_id);
    if ($check_user_article_dup->rows == 0) {
      $check_user_article_dup->finish;
      $dbh->do('update user_article set article = ?, bookmark = ? where user_article_id = ?', undef, $new_article_id, $new_article_id, $user_article_id);
    }
    else {
      my ($existing_user_article_id) = $check_user_article_dup->fetchrow_array;
      Bibliotech::Citation->retrieve($citation_id)->delete if $citation_id;
      soft_switch_user_article_tag($user_article_id, $existing_user_article_id);
      soft_switch_user_article_comment($user_article_id, $existing_user_article_id);
      $dbh->do('delete from user_article_details where user_article_id = ?', undef, $user_article_id);
      $dbh->do('delete from user_article where user_article_id = ?', undef, $user_article_id);
    }
  }
}

sub soft_switch_user_article_tag {
  my ($user_article_id, $existing_user_article_id) = @_;
  my $sth = $dbh->prepare('select user_article_tag_id, tag from user_article_tag where user_article = ?');
  $sth->execute($user_article_id);
  my $check_user_article_tag_dup = $dbh->prepare('select user_article_tag_id from user_article_tag where tag = ? and user_article = ?');
  while (my ($user_article_tag_id, $tag_id) = $sth->fetchrow_array) {
    $check_user_article_tag_dup->execute($tag_id, $existing_user_article_id);
    if ($check_user_article_tag_dup->rows == 0) {
      $check_user_article_tag_dup->finish;
      $dbh->do('update user_article_tag set user_article = ? where user_article_tag_id = ?', undef, $existing_user_article_id, $user_article_tag_id);
    }
    else {
      my ($existing_user_article_tag_id) = $check_user_article_tag_dup->fetchrow_array;
      $dbh->do('delete from user_article_tag where user_article_tag_id = ?', undef, $user_article_tag_id);
    }
  }
}

sub soft_switch_user_article_comment {
  my ($user_article_id, $existing_user_article_id) = @_;
  my $sth = $dbh->prepare('select user_article_comment_id, comment from user_article_comment where user_article = ?');
  $sth->execute($user_article_id);
  my $check_user_article_comment_dup = $dbh->prepare('select user_article_comment_id from user_article_comment where comment = ? and user_article = ?');
  while (my ($user_article_comment_id, $comment_id) = $sth->fetchrow_array) {
    $check_user_article_comment_dup->execute($comment_id, $existing_user_article_id);
    if ($check_user_article_comment_dup->rows == 0) {
      $check_user_article_comment_dup->finish;
      $dbh->do('update user_article_comment set user_article = ? where user_article_comment_id = ?', undef, $existing_user_article_id, $user_article_comment_id);
    }
    else {
      my ($existing_user_article_comment_id) = $check_user_article_comment_dup->fetchrow_array;
      $dbh->do('delete from user_article_comment where user_article_comment_id = ?', undef, $user_article_comment_id);
    }
  }
}

sub delete_transient_articles_sql {
  'delete from article where (select count(*) from bookmark where article = article_id) = 0 and (select count(*) from user_article where article = article_id) = 0';
}

sub delete_transient_articles {
  print "deleting transient article rows...\n";
  $dbh->do(delete_transient_articles_sql());
}

sub delete_orphaned_tags_annotations_sql {
  'delete from user_tag_annotation where (select count(*) from user_article_tag where user_tag_annotation.tag = user_article_tag.tag) = 0';
}

sub delete_orphaned_tags_sql {
  'delete from tag where (select count(*) from user_article_tag where tag = tag_id) = 0';
}

sub delete_orphaned_tags {
  print "deleting orphaned tag rows...\n";
  $dbh->do(delete_orphaned_tags_annotations_sql());
  $dbh->do(delete_orphaned_tags_sql());
}

sub delete_orphaned_comments_sql {
  'delete from comment where (select count(*) from user_article_comment where comment = comment_id) = 0 and (select count(*) from user where library_comment = comment_id) = 0 and (select count(*) from user_tag_annotation where comment = comment_id) = 0';
}

sub delete_orphaned_comments {
  print "deleting orphaned comment rows...\n";
  $dbh->do(delete_orphaned_comments_sql());
}

sub reconcat_multi_articles_sql {
  'select a.article_id, count(b.bookmark_id) from article a left join bookmark b on (b.article = a.article_id) group by a.article_id having count(b.bookmark_id) > 1';
}

sub reconcat_multi_articles {
  my $sth = $dbh->prepare(reconcat_multi_articles_sql());
  $sth->execute;
  while (my ($multi_article) = $sth->fetchrow_array) {
    reconcat_multi_articles_one($multi_article);
  }
}

sub reconcat_multi_articles_one {
  my $article_id = shift;
  print "reconcat $article_id\n";
  my $article = Bibliotech::Article->retrieve($article_id);
  errors_to_warnings(sub { $article->reconcat_citations; });
}

sub errors_to_warnings {
  my $action = shift;
  eval { $action->(); };
  warn $@ if $@;
}
