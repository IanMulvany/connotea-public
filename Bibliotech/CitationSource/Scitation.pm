package Bibliotech::CitationSource::Scitation;
use base 'Bibliotech::CitationSource';

use Bibliotech::CitationSource;
use Bibliotech::CitationSource::BibTeX;

use URI;
use URI::QueryParam;



# Site depends on session cookie
#
use LWP;
use HTTP::Request::Common;
use HTTP::Cookies;

sub api_version {
  1;
}

sub name {
  'Scitation / AIP';
}


sub cfgname {
  'Scitation';
}


sub understands {
  my ($self, $uri) = @_;

  #yes if already got the stuff
  return 1 if $self->{bibtex_cache};

  #check the host
  return 0 unless ($uri->scheme =~ /^http$/i);
  return 0 unless ($uri->host =~ m/^scitation\.aip\.org$/);

  # ex. http://scitation.aip.org/getabs/servlet/GetabsServlet?prog=normal&id=AOUSEK000051000007000S23000001&idtype=cvips&gifs=Yes
  return 1 if ($uri->path =~ m!/GetabsServlet!i) && $uri->query_param('id');

  #another ex: http://scitation.aip.org/vsearch/servlet/VerityServlet?KEY=FREESR&smode=results&maxdisp=10&possible1=charon&possible1zone=article&fromyear=1893&frommonth=Jan&toyear=2006&tomonth=Oct&OUTLOG=NO&viewabs=SJDMEC&key=DISPLAY&docID=6&page=0&chapter=0
  return 1 if ($uri->path =~ m!/VerityServlet!i) && $uri->query_param('viewabs');

  return 0;
}

# This needs to be used in scitation to get UR from BibTex/RIS file, instead of ugly url
sub filter {
	my ($self, $uri) = @_;

	$self->clear_bibtex_cache;
	my $bibtex = $self->get_bibtex($uri);

	my $url = $bibtex->UR;
	$url ? return new URI($url) : undef;
}

sub citations {
  my ($self, $article_uri) = @_;

  my $bibtex;
  eval {
    die "do not understand URI\n" unless $self->understands($article_uri);

    $bibtex = $self->get_bibtex($article_uri);

    die "BibTeX obj false\n" unless $bibtex;
    die "BibTeX file contained no data\n" unless $bibtex->has_data;
  };
  die $@ if $@ =~ /at .* line \d+/;
  $self->errstr($@), return undef if $@;
  return $bibtex->make_result(cfgname(), name())->make_resultlist;
}

sub clear_bibtex_cache {
    my ($self) = @_;
    undef $self->{bibtex_cache};
}

sub get_bibtex_content {
    my ($self, $uri) = @_;

    my $cookieJar = new HTTP::Cookies();
    my $ua = $self->ua;
    $ua->cookie_jar($cookieJar);

    # set/get session cookie (among others that may be automatically set)
    my $res = $ua->request(GET $uri);

    if($res->is_success) {
	
	my $id;

	if (($uri->path =~ m!/VerityServlet!i) && $uri->query_param('viewabs')) {
	    #need to scrape ID
	    my $id_stub = $uri->query_param('viewabs');
	    if ($res->content =~ m!<input\s+type="hidden"\s+name="SelectCheck"\s+value="($id_stub.*?)">!is) {
		$id = $1;
	    }
	    else {
		die "Couldn't extract ID from form";
	    }
	}
	elsif (($uri->path =~ m!/GetabsServlet!i) && $uri->query_param('id')) {
	    $id = $uri->query_param('id');
	}
	else {
	    die "No ID!";
	}
	    
	my $post_res = $ua->request(POST "http://" . $uri->host . "/getabs/servlet/GetCitation", [
					'fn' => 'open_bibtex2',
					'source' => 'scitation',
					'PrefType' => 'ARTICLE',
					'PrefAction' => 'Add Selected',
					'SelectCheck' => $id,
					
				    ]);
	if ($post_res->is_success) {

	    $bibtex_raw = $post_res->content;
	    
	    #fix bad bibtex that sometimes gets sent
	    $bibtex_raw =~ s/url = {(.+?)}\ndoi/url = {$1},\ndoi/s;
	    return $bibtex_raw;
	}
	else {
	    $self->errstr( $post_res->status_line );
	}
    }
    
    return;
}

sub get_bibtex {
	my ($self, $uri) = @_;

	# do we already have it?
	if($self->{bibtex_cache}) {
  	  return $self->{bibtex_cache};
	}

        my $bibtex_raw = $self->get_bibtex_content($uri);
        $self->{bibtex_cache} = Bibliotech::CitationSource::BibTeX->new($bibtex_raw);
	return $self->{bibtex_cache};
}

#true!
1;

