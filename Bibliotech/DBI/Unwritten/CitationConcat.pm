package Bibliotech::Unwritten::CitationConcat;
use strict;
use List::Util qw/reduce/;

# accept multiple citations (db or unwritten) and return an unwritten citation
# the returned citation is the concatenation of data from those provided
sub concat {
  reduce { concat_ab($a,$b) } @_;
}

# accept citations a & b and return concatenated citation c
sub concat_ab {
  my ($a, $b) = @_;
  Bibliotech::Unwritten::Citation->new
      ({title      	   => _simple_longer($a->title,      $b->title),
	volume     	   => _simple_longer($a->volume,     $b->volume),
	issue      	   => _simple_longer($a->issue,      $b->issue),
	start_page 	   => _simple_longer($a->start_page, $b->start_page),
	end_page   	   => _simple_longer($a->end_page,   $b->end_page),
	pubmed     	   => _simple_longer($a->pubmed,     $b->pubmed),
	doi        	   => _simple_longer($a->doi,        $b->doi),
	asin       	   => _simple_longer($a->asin,       $b->asin),
	ris_type   	   => _simple_longer($a->ris_type,   $b->ris_type),
	raw_date   	   => _simple_longer($a->raw_date,   $b->raw_date),
	date       	   => _simple_more_complete_date($a->date, $b->date),
	last_modified_date => _simple_more_complete_date($a->last_modified_date, $b->last_modified_date),
	user_supplied      => $a->user_supplied || $b->user_supplied || 0,
	journal    	   => _better_journal($a->journal, $b->journal),
	x_authors  	   => _better_authors([$a->authors], [$b->authors]),
	cs_module  	   => 'CitationConcat',
	cs_type    	   => 'Concatenated',
	cs_source  	   => _combine_id($a->cs_module, $a->cs_source, $a->citation_id,
					  $b->cs_module, $b->cs_source, $b->citation_id),
	cs_score   	   => 0,
	created    	   => undef,
       });
}

sub _simple_longer {
  my ($a, $b) = @_;
  return undef if not defined $a and not defined $b;
  return $a if not defined $b;
  return $b if not defined $a;
  return $a if length($a) >= length($b);
  return $b;
}

sub _simple_more_complete_date {
  my ($a, $b) = @_;
  return undef if not defined $a and not defined $b;
  return $a if not defined $b;
  return $b if not defined $a;
  (my $as = $a->iso8601) =~ s/x//g;
  (my $bs = $b->iso8601) =~ s/x//g;
  return $a if length($as) >= length($bs);
  return $b;
}

sub _combine_id {
  my ($a_module, $a_source, $a_id, $b_module, $b_source, $b_id) = @_;
  my $extract_id = sub { my ($module, $source, $id) = @_;
			 return $source if $module && $module eq 'CitationConcat';
			 return $id || 'unwritten'; };
  return join(',',
	      $extract_id->($a_module, $a_source, $a_id),
	      $extract_id->($b_module, $b_source, $b_id));
}

sub _better_journal {
  my ($a, $b) = @_;
  return undef if not defined $a and not defined $b;
  return $a if not defined $b;
  return $b if not defined $a;
  my $aj = $a->name || $a->medline_ta || $a->issn || '';
  my $bj = $b->name || $b->medline_ta || $b->issn || '';
  return $a if length($aj) >= length($bj);
  return $b;
}

sub _better_authors {
  my ($a, $b) = @_;
  my @a = @{$a||[]};
  my @b = @{$a||[]};
  return [] if !@a && !@b;
  return $a if !@b;
  return $b if !@a;
  return $a if @a > @b;
  return $b if @b > @a;
  for (my $i = 0; $i < @a; $i++) {
    my $ac = $a[$i]->name;
    my $bc = $b[$i]->name;
    return $a if length($ac) > length($bc);
    return $b if length($bc) > length($ac);
  }
  return $a;
}

sub _simple_eq {
  my ($a, $b) = @_;
  return 1 if not defined $a and not defined $b;
  return 0 if not defined $a;
  return 0 if not defined $b;
  return $a eq $b;
}

sub _simple_eq_date {
  my ($a, $b) = @_;
  return _simple_eq(defined $a ? $a->iso8601 : undef, defined $b ? $b->iso8601 : undef);
}

sub diff {
  diff_ab(@_);
}

sub diff_except_journal {
  grep { $_ ne 'journal' } diff(@_);
}

sub diff_ab {
  my ($a, $b) = @_;
  my @diff;
  push @diff, 'title'  	   	   unless _simple_eq($a->title,      $b->title);
  push @diff, 'volume' 	   	   unless _simple_eq($a->volume,     $b->volume);
  push @diff, 'issue'  	   	   unless _simple_eq($a->issue,      $b->issue);
  push @diff, 'start_page' 	   unless _simple_eq($a->start_page, $b->start_page);
  push @diff, 'end_page'   	   unless _simple_eq($a->end_page,   $b->end_page);
  push @diff, 'pubmed'     	   unless _simple_eq($a->pubmed,     $b->pubmed);
  push @diff, 'doi'        	   unless _simple_eq($a->doi,  	     $b->doi);
  push @diff, 'asin'       	   unless _simple_eq($a->asin, 	     $b->asin);
  push @diff, 'ris_type'   	   unless _simple_eq($a->ris_type,   $b->ris_type);
  push @diff, 'raw_date'   	   unless _simple_eq($a->raw_date,   $b->raw_date);
  push @diff, 'date'       	   unless _simple_eq_date($a->date,  $b->date);
  push @diff, 'last_modified_date' unless _simple_eq_date($a->last_modified_date, $b->last_modified_date);
  push @diff, 'user_supplied'      unless $a->user_supplied == $b->user_supplied;
  push @diff, 'journal'            unless _journal_eq($a->journal,   $b->journal);
  push @diff, 'authors'            unless _authors_eq([$a->authors], [$b->authors]);
  return @diff;
}

sub _journal_eq {
  my ($a, $b) = @_;
  return 1 if not defined $a and not defined $b;
  return 0 if not defined $b;
  return 0 if not defined $a;
  my $aj = $a->name || $a->medline_ta || $a->issn || '';
  my $bj = $b->name || $b->medline_ta || $b->issn || '';
  return $aj eq $bj;
}

sub _authors_eq {
  my ($a, $b) = @_;
  my @a = @{$a||[]};
  my @b = @{$a||[]};
  return 1 if !@a && !@b;
  return 0 if @a != @b;
  for (my $i = 0; $i < @a; $i++) {
    my $ac = $a[$i]->name;
    my $bc = $b[$i]->name;
    return 0 if $ac ne $bc;
  }
  return 1;
}

sub acceptable_existing {
  my $target = shift;
  defined $target or return;
  foreach (@_) {
    next unless defined $_;
    return $_ unless diff_except_journal($target, $_);
  }
  return;
}

# handle written and unwritten article and written and unwritten citation
sub _for_article_use_this_citation {
  my ($article, $citation) = @_;
  if ($article->isa('Bibliotech::Unwritten')) {
    $article->citation($citation);
  }
  else {
    $citation = $citation->write if $citation->isa('Bibliotech::Unwritten');
    my $current = $article->citation;
    if (!defined($current) or $current->citation_id != $citation->citation_id) {
      $article->citation($citation);
      $article->update;
      if (defined $current) {
	$current->delete if $current->bookmarks_or_user_articles_or_articles_count == 0;
      }
    }
  }
  return $article;
}

sub add_article_citation {
  my $article    = shift;
  my @citations  = $article->citations;
  my $new        = concat(@citations) or return $article;
  my $acceptable = acceptable_existing($new, $article->citation, @citations);
  return _for_article_use_this_citation($article, (defined $acceptable ? $acceptable : $new));
}

1;
__END__
