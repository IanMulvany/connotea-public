use strict;
use Bibliotech::CitationSource;
use Bibliotech::CitationSource::NPG;


package Bibliotech::CitationSource::Highwire;
use base 'Bibliotech::CitationSource';
use URI;
use URI::QueryParam;
use Data::Dumper;

# Necessary for integrating 'Science' plug-in into the Highwire plug-in
use LWP;
use HTTP::Request::Common;

sub api_version {
  1;
}

sub name {
  'Highwire';
}

sub version {
  '1.7.6.1';
}

sub understands {
  my ($self, $uri, $ris_host) = @_;
  return 0 unless $uri->scheme eq 'http';
  return 0 unless Bibliotech::CitationSource::Highwire::HostTable::defined($uri->host);
  return 1 if ($uri->path =~ m!^/cgi/((content/(summary|short|extract|abstract|full))|reprint)/(${ris_host};)?.+!i);
  return 0;
}

sub citations {
  my ($self, $article_uri) = @_;

  my $ris;
  eval {
    my $ris_host = Bibliotech::CitationSource::Highwire::HostTable::getRISPrefix($article_uri->host);
    #
    # Some entries will require a login/password; structure in hash is a reference not scalar
    #
    my $ris_login;
    if (ref($ris_host)) {
      $ris_login = $self->highwire_account($ris_host->{ACCT_TYPE});
      $ris_host = $ris_host->{RIS_PREFIX};	# re-assign this as a scalar
    }

    my $file = $article_uri->path;
    $file =~ s/(?:#|\?).*//;  # strip fragments or queries

    die "no file name seen in URI\n" unless $file;

    #find the ID
    my $id;
    if ($file =~ m!^/cgi/(?:(?:content/(?:summary|short|extract|abstract|full))|reprint)/(?:${ris_host};)?(.+)$!i) {
      $id = $1;
    }

    die "Couldn't extract Highwire ID\n" unless $id;

    my $query_uri = URI->new('http://'.$article_uri->host.'/cgi/citmgr?type=refman&gca='.$ris_host.';'.$id);

    #
    # use query w/ authorization if needed
    #
    my $ris_raw;
    my $ua;
    my $response;
    if ($ris_login) {
      $ua = $self->ua;
      $response = $ua->request(POST $query_uri, [ 'username' => $ris_login->{USER}, 'code' => $ris_login->{PW}]);
      if ($response->is_success) {
        $ris_raw = $response->decoded_content;
      } else {
        die $response->status_line;
      }
    } else {
      $ris_raw = $self->get($query_uri);
    }

    # Note: DOI comes in N1 -- see inline modules below.

    $ris = Bibliotech::CitationSource::NPG::RIS->new($ris_raw);

    if (!$ris->has_data) {
      # give it one more try 
      sleep 2;

      if ($ris_login) {
	$response = $ua->request(POST $query_uri, [ 'username' => $ris_login->{USER}, 'code' => $ris_login->{PW}]);
	if($response->is_success) {
	  $ris_raw = $response->decoded_content;
	} else {
	  die $response->status_line;
	}
      } else {
	$ris_raw = $self->get($query_uri);
      }

      $ris = new Bibliotech::CitationSource::NPG::RIS ($ris_raw);
    }
    die "RIS obj false\n" unless $ris;
    die "RIS file contained no data\n" unless $ris->has_data;
  };
  if (my $e = $@) {
    die $e if $e =~ /at .* line \d+/;
    if ($e eq "RIS file contained no data\n") {  # happens a lot
      $self->warnstr($e);
    }
    else {
      $self->errstr($e);
    }
    return undef;
  }

  return bless [bless $ris, 'Bibliotech::CitationSource::Highwire::Result'], 'Bibliotech::CitationSource::ResultList';
}

#
# Necessary for integrating 'Science' plug-in into the Highwire plug-in
#	'Science' requires login/password to get citation data
#   Add other login/pw as needed; follow science model in bibliotech.conf
#   Then add conditional for new "acct_type"
#
sub user {
  my ($self, $var) = @_;
  shift->cfg($var);
}

sub password {
  my ($self, $var) = @_;
  shift->cfg($var);
}

sub highwire_account {
  my($self, $acct_type) = @_;

  my $login;
  if ($acct_type eq 'SCIENCE') {
    $login->{USER} = $self->user('SCI_USER');
    $login->{PW} = $self->password('SCI_PASSWORD');
  }

  ($login->{USER} && $login->{PW}) ? return $login : return undef;
}


package Bibliotech::CitationSource::Highwire::Result;
use base ('Bibliotech::CitationSource::NPG::RIS', 'Bibliotech::CitationSource::Result');

sub type {
  'Highwire';
}

sub source {
  'Highwire RIS file';
}

sub identifiers {
  {doi => shift->doi};
}

sub justone {
  my ($self, $field) = @_;
  my $super = 'SUPER::'.$field;
  my $stored = $self->$super or return undef;
  return ref $stored ? $stored->[0] : $stored;
}

sub authors {
  my ($self) = @_;
  my $authors = $self->SUPER::authors;
  my @authors = map(Bibliotech::CitationSource::Highwire::Result::Author->new($_), ref $authors ? @{$authors} : $authors);
  bless \@authors, 'Bibliotech::CitationSource::Result::AuthorList';
}

# override - from Nature the abbreviated name arrives in JO
sub periodical_name  { shift->collect(qw/JF/); }
sub periodical_abbr  { shift->collect(qw/JO JA J1 J2/); }

sub journal {
  my ($self) = @_;
  return Bibliotech::CitationSource::Highwire::Result::Journal->new($self->justone('journal'),
							 $self->justone('journal_abbr'),
							 $self->justone('issn'));
}

sub pubmed  { undef; }
sub doi     { shift->collect(qw/N1/); }
sub title   { shift->justone('title'); }
sub volume  { shift->justone('volume'); }
sub issue   { shift->justone('issue'); }
sub page    { shift->page_range; }
sub url     { shift->collect(qw/UR L3/); }

sub date {
  my $date = shift->justone('date');
  $date =~ s|^(\d+/\d+/\d+)/.*$|$1|;
  return $date;
}

sub last_modified_date {
  shift->date(@_);
}

package Bibliotech::CitationSource::Highwire::Result::Author;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/firstname forename initials lastname/);

sub new {
  my ($class, $author) = @_;
  my $self = {};
  bless $self, ref $class || $class;
  my ($lastname, $firstname);
  if ($author =~ /^(.+?),\s*(.*)$/) {
    ($lastname, $firstname) = ($1, $2);
  }
  elsif ($author =~ /^(.*)\s+(.+)$/) {
    ($firstname, $lastname) = ($1, $2);
  }
  else {
    $lastname = $author;
  }
  $self->forename($firstname);
  my $initials = join(' ', map { s/^(.).*$/$1/; $_; } split(/\s+/, $firstname)) || undef;
  $firstname =~ s/(\s\w\.?)+$//;
  $self->firstname($firstname);
  $self->lastname($lastname);
  $self->initials($initials);
  return $self;
}

package Bibliotech::CitationSource::Highwire::Result::Journal;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/name medline_ta issn/);

sub new {
  my ($class, $name, $medline_ta, $issn) = @_;
  my $self = {};
  bless $self, ref $class || $class;
  $self->name($name);
  $self->medline_ta($medline_ta);
  $self->issn($issn);
  return $self;
}

package Bibliotech::CitationSource::Highwire::HostTable;

%Bibliotech::CitationSoure::Highwire::HostTable::Hosts = (

  #Archives of General Psychiatry
  'archpsyc.ama-assn.org'               =>          'archpsyc',

  #Mutagenesis
  'mutage.oupjournals.org'               =>          'mutage',

  #Visual Communication
  'vcj.sagepub.com'               =>          'spvcj',

  #Social Science Computer Review
  'ssc.sagepub.com'               =>          'spssc',

  #Studies in Christian Ethics
  'sce.sagepub.com'               =>          'spsce',

  #Stem Cells
  'stemcells.alphamedpress.org'               =>          'stemcells',

  #QJM
  'qjmed.oupjournals.org'               =>          'qjmed',

  #Journal of Virology
  'jvi.asm.org'               =>          'jvi',

  #International Journal for Quality in Health Care
  'intqhc.oupjournals.org'               =>          'intqhc',

  #Environment and Behavior
  'eab.sagepub.com'               =>          'speab',

  #Gender & Society
  'gas.sagepub.com'               =>          'spgas',

  #Educational Policy
  'epx.sagepub.com'               =>          'spepx',

  #Critique of Anthropology
  'coa.sagepub.com'               =>          'spcoa',

  #Journal of Epidemiology & Community Health
  'jech.bmjjournals.com'               =>          'jech',

  #Journal of Conflict Resolution
  'jcr.sagepub.com'               =>          'spjcr',

  #The World Bank Research Observer
  'wbro.oupjournals.org'               =>          'wbro',

  #Family and Consumer Sciences Research Journal
  'fcs.sagepub.com'               =>          'spfcs',

  #Endocrine Reviews
  'edrv.endojournals.org'               =>          'edrv',

  #The EMBO Journal
  'embojournal.npgjournals.com'               =>          'emboj',

  #Journal of Macromarketing
  'jmk.sagepub.com'               =>          'spjmk',

  #Oxford Review of Economic Policy
  'oxrep.oupjournals.org'               =>          'oxrep',

  #Journal of European Social Policy
  'esp.sagepub.com'               =>          'spesp',

  #Cancer Epidemiology Biomarkers & Prevention
  'cebp.aacrjournals.org'               =>          'cebp',

  #American Journal of Clinical Nutrition
  'www.ajcn.org'               =>          'ajcn',

  #The Journal of Foraminiferal Research
  'jfr.geoscienceworld.org'               =>          'gsjfr',

  #Industrial and Corporate Change
  'icc.oupjournals.org'               =>          'indcor',

  #Genes & Development
  'www.genesdev.org'               =>          'genesdev',

  #International Journal of Lexicography
  'ijl.oupjournals.org'               =>          'lexico',

  #The International Journal of Robotics Research
  'ijr.sagepub.com'               =>          'spijr',

  #American Journal of Respiratory Cell and Molecular Biology
  'www.ajrcmb.org'               =>          'ajrcmb',

  #Journal of Holistic Nursing
  'jhn.sagepub.com'               =>          'spjhn',

  #Graft
  'gft.sagepub.com'               =>          'spgft',

  #Childhood
  'chd.sagepub.com'               =>          'spchd',

  #Journal of Consumer Culture
  'joc.sagepub.com'               =>          'spjoc',

  #The Plant Cell Online
  'www.plantcell.org'               =>          'plantcell',

  #Research on Social Work Practice
  'rsw.sagepub.com'               =>          'sprsw',

  #International Political Science Review/ Revue internationale de science politique
  'ips.sagepub.com'               =>          'spips',

  #Youth & Society
  'yas.sagepub.com'               =>          'spyas',

  #Journal of European Studies
  'jes.sagepub.com'               =>          'spjes',

  #French Studies
  'fs.oupjournals.org'               =>          'frestu',

  #Journal of Intelligent Material Systems and Structures
  'jim.sagepub.com'               =>          'spjim',

  #Qualitative Inquiry
  'qix.sagepub.com'               =>          'spqix',

  #European Journal of Endocrinology
  'www.eje-online.org'               =>          'eje',

  #Journal of Bioactive and Compatible Polymers
  'jbc.sagepub.com'               =>          'spjbc',

  #American Journal of Public Health
  'www.ajph.org'               =>          'ajph',

  #Structural Health Monitoring
  'shm.sagepub.com'               =>          'spshm',

  #International Studies
  'isq.sagepub.com'               =>          'spisq',

  #Geology
  'geology.geoscienceworld.org'               =>          'gsgeology',

  #EMBO Reports
  'emboreports.npgjournals.com'               =>          'emborep',

  #Journal of Pharmacy Practice
  'jpp.sagepub.com'               =>          'spjpp',

  #Journal of Nuclear Medicine
  'jnm.snmjournals.org'               =>          'jnumed',

  #Journal of Psychotherapy Practice and Research
  'jppr.psychiatryonline.org'               =>          'jppr',

  #Work and Occupations
  'wox.sagepub.com'               =>          'spwox',

  #International Review for the Sociology of Sport
  'irs.sagepub.com'               =>          'spirs',

  #IEICE Transactions on Communications
  'ietcom.oupjournals.org'               =>          'ietcom',

  #Forum for Modern Language Studies
  'fmls.oupjournals.org'               =>          'formod',

  #The Medieval History Journal
  'mhj.sagepub.com'               =>          'spmhj',

  #British Journal of Criminology
  'bjc.oupjournals.org'               =>          'crimin',

  #The European Journal of Orthodontics
  'ejo.oupjournals.org'               =>          'eortho',

  #Journal of Anglican Studies
  'ast.sagepub.com'               =>          'spast',

  #Homicide Studies
  'hsx.sagepub.com'               =>          'sphsx',

  #Qualitative Health Research
  'qhr.sagepub.com'               =>          'spqhr',

  #The Journal of Physiology
  'jp.physoc.org'               =>          'jphysiol',

  #Infection and Immunity
  'iai.asm.org'               =>          'iai',

  #Mineralogical Magazine
  'minmag.geoscienceworld.org'               =>          'gsminmag',

  #Advances in Developing Human Resources
  'adh.sagepub.com'               =>          'spadh',

  #Bulletin of Science, Technology & Society
  'bst.sagepub.com'               =>          'spbst',

  #Journal of the American Podiatric Medical Association
  'www.japmaonline.org'               =>          'jpodma',

  #Annals of Oncology
  'annonc.oupjournals.org'               =>          'annonc',

  #Journal of Health Psychology
  'hpq.sagepub.com'               =>          'sphpq',

  #Journal of Marketing Education
  'jmd.sagepub.com'               =>          'spjmd',

  #SIMULATION
  'sim.sagepub.com'               =>          'spsim',

  #Chest
  'www.chestjournal.org'               =>          'chest',

  #Antimicrobial Agents and Chemotherapy
  'aac.asm.org'               =>          'aac',

  #Molecular Cancer Research
  'mcr.aacrjournals.org'               =>          'molcanres',

  #Molecular and Cellular Biology
  'mcb.asm.org'               =>          'mcb',

  #International Journal of Cultural Studies
  'ics.sagepub.com'               =>          'spics',

  #Nursing Science Quarterly
  'nsq.sagepub.com'               =>          'spnsq',

  #The Journal of Applied Behavioral Science
  'jab.sagepub.com'               =>          'spjab',

  #Recent Progress in Hormone Research
  'rphr.endojournals.org'               =>          'rphr',

  #The Diabetes Educator
  'tde.sagepub.com'               =>          'sptde',

  #Palynology
  'palynology.geoscienceworld.org'               =>          'gspalynol',

  #Archives of Internal Medicine
  'archinte.ama-assn.org'               =>          'archinte',

  #Teaching Mathematics and its Applications
  'teamat.oupjournals.org'               =>          'teamat',

  #Journal of Planning History
  'jph.sagepub.com'               =>          'spjph',

  #Journal of Sociology
  'jos.sagepub.com'               =>          'spjos',

  #International Journal of Law and Information Technology
  'ijlit.oupjournals.org'               =>          'inttec',

  #Journal of Semitic Studies
  'jss.oupjournals.org'               =>          'semitj',

  #Mycologia
  'www.mycologia.org'               =>          'mycologia',

  #High Performance Polymers
  'hip.sagepub.com'               =>          'sphip',

  #Management Learning
  'mlq.sagepub.com'               =>          'spmlq',

  #Biophysical Journal
  'www.biophysj.org'               =>          'biophysj',

  #Evaluation
  'evi.sagepub.com'               =>          'spevi',

  #Biostatistics
  'biostatistics.oupjournals.org'               =>          'biosts',

  #Business Information Review
  'bir.sagepub.com'               =>          'spbir',

  #Psychiatric Services
  'psychservices.psychiatryonline.org'               =>          'ps',

  #JAMA
  'jama.ama-assn.org'               =>          'jama',

  #Evidence-based Complementary and Alternative Medicine
  'ecam.oupjournals.org'               =>          'ecam',

  #Geochemistry: Exploration, Environment, Analysis
  'geea.geoscienceworld.org'               =>          'gsgeochem',

  #Business Communication Quarterly
  'bcq.sagepub.com'               =>          'spbcq',

  #Economic Geology
  'econgeol.geoscienceworld.org'               =>          'gsecongeo',

  #Plant and Cell Physiology
  'pcp.oupjournals.org'               =>          'pcellphys',

  #European Journal of Industrial Relations
  'ejd.sagepub.com'               =>          'spejd',

  #International Social Work
  'isw.sagepub.com'               =>          'spisw',

  #Criminal Justice Policy Review
  'cjp.sagepub.com'               =>          'spcjp',

  #Journal of Experimental Medicine
  'www.jem.org'               =>          'jem',

  #Crop Science
  'crop.scijournals.org'               =>          'cropsci',

  #Biology of Reproduction
  'www.biolreprod.org'               =>          'biolreprod',

  #Family Practice
  'fampra.oupjournals.org'               =>          'fampract',

  #Journal of Clinical Microbiology
  'jcm.asm.org'               =>          'jcm',

  #Journal of Planning Education and Research
  'jpe.sagepub.com'               =>          'spjpe',

  #Imaging
  'imaging.birjournals.org'               =>          'imaging',

  #Group & Organization Management
  'gom.sagepub.com'               =>          'spgom',

  #Clinical Child Psychology and Psychiatry
  'ccp.sagepub.com'               =>          'spccp',

  #Forestry
  'forestry.oupjournals.org'               =>          'foresj',

  #Plant Physiology
  'www.plantphysiol.org'               =>          'plantphysiol',

  #Chemical Senses
  'chemse.oupjournals.org'               =>          'chemse',

  #Journals of Gerontology Series B: Psychological Sciences and Social Sciences
  'psychsoc.gerontologyjournals.org'               =>          'jgerob',

  #Cerebral Cortex
  'cercor.oupjournals.org'               =>          'cercor',

  #Young
  'you.sagepub.com'               =>          'spyou',

  #Gender, Technology and Development
  'gtd.sagepub.com'               =>          'spgtd',

  #Journal of Composite Materials
  'jcm.sagepub.com'               =>          'spjcm',

  #British Journal of Sports Medicine
  'bjsm.bmjjournals.com'               =>          'bjsports',

  #IEICE Transactions on Information and Systems
  'ietisy.oupjournals.org'               =>          'ietisy',

  #Journal of Child Health Care
  'chc.sagepub.com'               =>          'spchc',

  #Journal of Attention Disorders
  'jad.sagepub.com'               =>          'spjad',

  #Diogenes
  'dio.sagepub.com'               =>          'spdio',

  #Archives of Disease in Childhood
  'adc.bmjjournals.com'               =>          'archdischild',

  #Journal for the Study of the Historical Jesus
  'jhj.sagepub.com'               =>          'spjhj',

  #Behavior Modification
  'bmo.sagepub.com'               =>          'spbmo',

  #Journal of Research in Crime and Delinquency
  'jrc.sagepub.com'               =>          'spjrc',

  #European Journal of Communication
  'ejc.sagepub.com'               =>          'spejc',

  #Journal of Moral Philosophy
  'mpj.sagepub.com'               =>          'spmpj',

  #Asia Pacific Journal of Human Resources
  'apj.sagepub.com'               =>          'spapj',

  #Ethnicities
  'etn.sagepub.com'               =>          'spetn',

  #Journal of Management Inquiry
  'jmi.sagepub.com'               =>          'spjmi',

  #Occupational and Environmental Medicine
  'oem.bmjjournals.com'               =>          'oemed',

  #Review of Financial Studies
  'rfs.oupjournals.org'               =>          'revfin',

  #The World Bank Economic Review
  'wber.oupjournals.org'               =>          'wber',

  #The Journal of Bone and Joint Surgery
  'www.ejbjs.org'               =>          'jobojos',

  #Journal of Planning Literature
  'jpl.sagepub.com'               =>          'spjpl',

  #Journal of Wide Bandgap Materials
  'jwb.sagepub.com'               =>          'spjwb',

  #Journal of Thermoplastic Composite Materials
  'jtc.sagepub.com'               =>          'spjtc',

  #European Journal of Women's Studies
  'ejw.sagepub.com'               =>          'spejw',

  #Journal of Clinical Endocrinology & Metabolism
  'jcem.endojournals.org'               =>          'jcem',

  #Journal of Environmental Law
  'jel.oupjournals.org'               =>          'envlaw',

  #Critical Social Policy
  'csp.sagepub.com'               =>          'spcsp',

  #The ANNALS of the American Academy of Political and Social Science
  'ann.sagepub.com'               =>          'spann',

  #Journal of Plastic Film and Sheeting
  'jpf.sagepub.com'               =>          'spjpf',

  #Archives of Ophthalmology
  'archopht.ama-assn.org'               =>          'archopht',

  #Microbiology and Molecular Biology Reviews
  'mmbr.asm.org'               =>          'mmbr',

  #Criminal Justice and Behavior
  'cjb.sagepub.com'               =>          'spcjb',

  #Tourist Studies
  'tou.sagepub.com'               =>          'sptou',

  #Archives of Surgery
  'archsurg.ama-assn.org'               =>          'archsurg',

  #The British Journal for the Philosophy of Science
  'bjps.oupjournals.org'               =>          'phisci',

  #European Union Politics
  'eup.sagepub.com'               =>          'speup',

  #The International Journal of Lower Extremity Wounds
  'ijl.sagepub.com'               =>          'spijl',

  #Review of Radical Political Economics
  'rrp.sagepub.com'               =>          'sprrp',

  #Complementary Health Practice Review
  'chp.sagepub.com'               =>          'spchp',

  #Journal of Social and Personal Relationships
  'spr.sagepub.com'               =>          'spspr',

  #Genetics
  'www.genetics.org'               =>          'genetics',

  #Journal of Wildlife Diseases
  'www.jwildlifedis.org'               =>          'wildlifedis',

  #Contemporary Economic Policy
  'cep.oupjournals.org'               =>          'coneco',

  #Journal of Peace Research
  'jpr.sagepub.com'               =>          'spjpr',

  #New England Journal of Medicine
  'content.nejm.org'               =>          'nejm',

  #Language and Literature
  'lal.sagepub.com'               =>          'splal',

  #Focus
  'focus.psychiatryonline.org'               =>          'focus',

  #Psychiatric News
  'pn.psychiatryonline.org'                    =>      'psychnews', 

  #JPEN- Journal of Parenteral and Enteral Nutrition
  'jpen.aspenjournals.org'               =>          'jpen',

  #Improving Schools
  'imp.sagepub.com'               =>          'spimp',

  #The Veterinary Record
  'veterinaryrecord.bvapublications.com'               =>          'vetrecord',

  #Reproduction
  'www.reproduction-online.org'               =>          'reprod',

  #Journal of Research in Nursing
  'jrn.sagepub.com'               =>          'spjrn',

  #Journal of Neuroimaging
  'jon.sagepub.com'               =>          'spjon',

  #Crime & Delinquency
  'cad.sagepub.com'               =>          'spcad',

  #The Journal of Theological Studies
  'jts.oupjournals.org'               =>          'theolj',

  #Economic Development Quarterly
  'edq.sagepub.com'               =>          'spedq',

  #Health Education & Behavior
  'heb.sagepub.com'               =>          'spheb',

  #The Prison Journal
  'tpj.sagepub.com'               =>          'sptpj',

  #Dementia
  'dem.sagepub.com'               =>          'spdem',

  #Mathematical Medicine and Biology
  'imammb.oupjournals.org'               =>          'imammb',

  #Journal of Hispanic Higher Education
  'jhh.sagepub.com'               =>          'spjhh',

  #Socio-Economic Review
  'ser.oupjournals.org'               =>          'soceco',

  #American Journal of Physiology - Cell Physiology
  'ajpcell.physiology.org'               =>          'ajpcell',

  #Alcohol and Alcoholism
  'alcalc.oupjournals.org'               =>          'alcalc',

  #Theory & Psychology
  'tap.sagepub.com'               =>          'sptap',

  #Human Resource Development Review
  'hrd.sagepub.com'               =>          'sphrd',

  #Applied Linguistics
  'applij.oupjournals.org'               =>          'applij',

  #Acta Sociologica
  'asj.sagepub.com'               =>          'spasj',

  #Theoretical Criminology
  'tcr.sagepub.com'               =>          'sptcr',

  #The Journal of Thoracic and Cardiovascular Surgery
  'jtcs.ctsnetjournals.org'               =>          'jtcs',

  #Journal of Entrepreneurship
  'joe.sagepub.com'               =>          'spjoe',

  #Global Business Review
  'gbr.sagepub.com'               =>          'spgbr',

  #Journal of Endocrinology
  'joe.endocrinology-journals.org'               =>          'joe',

  #Nephrology Dialysis Transplantation
  'ndt.oupjournals.org'               =>          'ndt',

  #Obstetrics & Gynecology
  'www.greenjournal.org'               =>          'acogjnl',

  #Journal of Urban History
  'juh.sagepub.com'               =>          'spjuh',

  #Emotional & Behavioural Difficulties
  'ebd.sagepub.com'               =>          'spebd',

  #IEICE Transactions on Fundamentals of Electronics, Communications and Computer Sciences
  'ietfec.oupjournals.org'               =>          'ietfec',

  #Theory, Culture & Society
  'tcs.sagepub.com'               =>          'sptcs',

  #China Report
  'chr.sagepub.com'               =>          'spchr',

  #Gazette
  'gaz.sagepub.com'               =>          'spgaz',

  #Indian Journal of Gender Studies
  'ijg.sagepub.com'               =>          'spijg',

  #Journal of the History of Medicine and Allied Sciences
  'jhmas.oupjournals.org'               =>          'jalsci',

  #Journal of Bacteriology
  'jb.asm.org'               =>          'jb',

  #Toxicological Sciences
  'toxsci.oupjournals.org'               =>          'toxsci',

  #Journals of Gerontology Series A: Biological and Medical Sciences
  'biomed.gerontologyjournals.org'               =>          'jgeroa',

  #International Journal of Cross Cultural Management
  'ccm.sagepub.com'               =>          'spccm',

  #IMA Journal of Management Mathematics
  'imaman.oupjournals.org'               =>          'imaman',

  #Public Understanding of Science
  'pus.sagepub.com'               =>          'sppus',

  #Trauma, Violence, & Abuse
  'tva.sagepub.com'               =>          'sptva',

  #Journal of Asian and African Studies
  'jas.sagepub.com'               =>          'spjas',

  #French Cultural Studies
  'frc.sagepub.com'               =>          'spfrc',

  #Strategic Organization
  'soq.sagepub.com'               =>          'spsoq',

  #Physiological Reviews
  'physrev.physiology.org'               =>          'physrev',

  #The Review of English Studies
  'res.oupjournals.org'               =>          'revesj',

  #Vadose Zone Journal
  'vzj.scijournals.org'               =>          'vadzone',

  #Injury Prevention
  'ip.bmjjournals.com'               =>          'injuryprev',

  #Evidence Based Mental Health
  'ebmh.bmjjournals.com'                 =>       'ebmental',

  #Journal for the Study of the Old Testament
  'jot.sagepub.com'               =>          'spjot',

  #Journal of Language and Social Psychology
  'jls.sagepub.com'               =>          'spjls',

  #Human Relations
  'hum.sagepub.com'               =>          'sphum',

  #Journal of Travel Research
  'jtr.sagepub.com'               =>          'spjtr',

  #Oxford Journal of Legal Studies
  'ojls.oupjournals.org'               =>          'oxjlsj',

  #Journal of Neurophysiology
  'jn.physiology.org'               =>          'jn',

  #Integrative Cancer Therapies
  'ict.sagepub.com'               =>          'spict',

  #Journal of Pediatric Oncology Nursing
  'jpo.sagepub.com'               =>          'spjpo',

  #Protein Engineering Design and Selection
  'peds.oupjournals.org'               =>          'proeng',

  #Annals of Surgical Oncology
  'www.annalssurgicaloncology.org'               =>          'annso',

  #Glycobiology
  'glycob.oupjournals.org'               =>          'glycob',

  #Geological Magazine
  'geolmag.geoscienceworld.org'               =>          'gsgeolmag',

  #American Journal of Psychiatry
  'ajp.psychiatryonline.org'               =>          'ajp',

  #Health Education Research
  'her.oupjournals.org'               =>          'her',

  #Molecular Human Reproduction
  'molehr.oupjournals.org'               =>          'molehr',

  #Field Methods
  'fmx.sagepub.com'               =>          'spfmx',

  #Journal of Communication
  'joc.oupjournals.org'               =>          'jnlcom',

  #Feminist Theory
  'fty.sagepub.com'               =>          'spfty',

  #Cornell Hotel and Restaurant Administration Quarterly
  'cqx.sagepub.com'               =>          'spcqx',

  #Journal of Public Health
  'jpubhealth.oupjournals.org'               =>          'jphm',

  #Clinical Microbiology Reviews
  'cmr.asm.org'               =>          'cmr',

  #Holocaust and Genocide Studies
  'hgs.oupjournals.org'               =>          'holgen',

  #BMJ
  'www.bmj.com'               =>          'bmj',

  #Physiology
  'www.physiologyonline.org'               =>          'nips',

  #Probation Journal
  'prb.sagepub.com'               =>          'spprb',

  #Journal of Medical Microbiology
  'jmm.sgmjournals.org'               =>          'medmicro',

  #Environment and Urbanization
  'eau.sagepub.com'               =>          'speau',

  #Arteriosclerosis, Thrombosis, and Vascular Biology
  'atvb.ahajournals.org'               =>          'atvbaha',

  #Science Technology & Society
  'sts.sagepub.com'               =>          'spsts',

  #Written Communication
  'wcx.sagepub.com'               =>          'spwcx',

  #Journal of Medical Ethics
  'jme.bmjjournals.com'               =>          'medethics',

  #Clinical Psychology: Science and Practice
  'clipsy.oupjournals.org'               =>          'clipsy',

  #American Journal of Physiology - Renal Physiology
  'ajprenal.physiology.org'               =>          'ajprenal',

  #Anthropological Theory
  'ant.sagepub.com'               =>          'spant',

  #Journal of Communication Inquiry
  'jci.sagepub.com'               =>          'spjci',

  #Human Reproduction
  'humrep.oupjournals.org'               =>          'humrep',

  #Journal of Early Childhood Research
  'ecr.sagepub.com'               =>          'specr',

  #Journal of Clinical Investigation
  'www.jci.org'               =>          'jci',

  #International Journal of High Performance Computing Applications
  'hpc.sagepub.com'               =>          'sphpc',

  #Journal of Social Archaeology
  'jsa.sagepub.com'               =>          'spjsa',

  #Violence Against Women
  'vaw.sagepub.com'               =>          'spvaw',

  #Journal of Visual Culture
  'vcu.sagepub.com'               =>          'spvcu',

  #Journal of Design History
  'jdh.oupjournals.org'               =>          'design',

  #The Quarterly Journal of Mathematics
  'qjmath.oupjournals.org'               =>          'qmathj',

  #European Urban and Regional Studies
  'eur.sagepub.com'               =>          'speur',

  #Youth Violence and Juvenile Justice
  'yvj.sagepub.com'               =>          'spyvj',

  #Journal of Sandwich Structures and Materials
  'jsm.sagepub.com'               =>          'spjsm',

  #Journal of Paleontology
  'jpaleontol.geoscienceworld.org'               =>          'gsjpaleo',

  #Screen
  'screen.oupjournals.org'               =>          'screen',

  #Mind
  'mind.oupjournals.org'               =>          'mind',

  #Journal of Contemporary Ethnography
  'jce.sagepub.com'               =>          'spjce',

  #Investigative Ophthalmology & Visual Science
  'www.iovs.org'               =>          'iovs',

  #American Journal of Physiology - Endocrinology And Metabolism
  'ajpendo.physiology.org'               =>          'ajpendo',

  #Endocrinology
  'endo.endojournals.org'               =>          'endo',

  #American Journal of Physiology - Heart and Circulatory Physiology
  'ajpheart.physiology.org'               =>          'ajpheart',

  #Journal of Clinical Oncology
  'www.jco.org'               =>          'jco',

  #Rationality and Society
  'rss.sagepub.com'               =>          'sprss',

  #Journal of Electron Microscopy
  'jmicro.oupjournals.org'               =>          'jmicro',

  #The Cambridge Quarterly
  'camqtly.oupjournals.org'               =>          'camquj',

  #Public Finance Review
  'pfr.sagepub.com'               =>          'sppfr',

  #Psychiatric Bulletin
  'pb.rcpsych.org'               =>          'pbrcpsych',

  #Social Science Japan Journal
  'ssjj.oupjournals.org'               =>          'ssjapj',

  #African Affairs
  'afraf.oupjournals.org'               =>          'afrafj',

  #Journal of Industrial Textiles
  'jit.sagepub.com'               =>          'spjit',

  #JAOA: Journal of the American Osteopathic Association
  'www.jaoa.org'               =>          'jaoa',

  #IMA Journal of Mathematical Control and Information
  'imamci.oupjournals.org'               =>          'imamci',

  #The Journal of General Physiology
  'www.jgp.org'               =>          'jgp',

  #Journal of Orthodontics
  'jorthod.maneyjournals.org'               =>          'ortho',

  #Journal of Leukocyte Biology
  'www.jleukbio.org'               =>          'jleub',

  #Journal of Black Studies
  'jbs.sagepub.com'               =>          'spjbs',

  #Review of Public Personnel Administration
  'rop.sagepub.com'               =>          'sprop',

  #Journal of the Academy of Marketing Science
  'jam.sagepub.com'               =>          'spjam',

  #Biochemistry and Molecular Biology Education
  'www.bambed.org'               =>          'bambed',

  #European Review of Agricultural Economics
  'erae.oupjournals.org'               =>          'eurrag',

  #International Sociology
  'iss.sagepub.com'               =>          'spiss',

  #Protein Science
  'www.proteinscience.org'               =>          'protsci',

  #Party Politics
  'ppq.sagepub.com'               =>          'spppq',

  #Cancer Research
  'cancerres.aacrjournals.org'               =>          'canres',

  #Concurrent Engineering
  'cer.sagepub.com'               =>          'spcer',

  #Autism
  'aut.sagepub.com'               =>          'spaut',

  #Journal of Antimicrobial Chemotherapy
  'jac.oupjournals.org'               =>          'jac',

  #Television & New Media
  'tvn.sagepub.com'               =>          'sptvn',

  #Business & Society
  'bas.sagepub.com'               =>          'spbas',

  #Journal of English Linguistics
  'eng.sagepub.com'               =>          'speng',

  #Administration & Society
  'aas.sagepub.com'               =>          'spaas',

  #Waste Management & Research
  'wmr.sagepub.com'               =>          'spwmr',

  #Journal of Histochemistry and Cytochemistry
  'www.jhc.org'               =>          'jhc',

  #Social Politics: International Studies in Gender, State & Society
  'sp.oupjournals.org'               =>          'socpol',

  #Chinese Journal of International Law
  'chinesejil.oupjournals.org'               =>          'cjilaw',

  #Postgraduate Medical Journal
  'pmj.bmjjournals.com'               =>          'postgradmedj',

  #Sexually Transmitted Infections
  'sti.bmjjournals.com'               =>          'sextrans',

  #Journal of Librarianship and Information Science
  'lis.sagepub.com'               =>          'splis',

  #ELT Journal
  'eltj.oupjournals.org'               =>          'eltj',

  #Journal of Developing Societies
  'jds.sagepub.com'               =>          'spjds',

  #Small Group Research
  'sgr.sagepub.com'               =>          'spsgr',

  #American Journal of Physiology - Gastrointestinal and Liver Physiology
  'ajpgi.physiology.org'               =>          'ajpgi',

  #Marketing Theory
  'mtq.sagepub.com'               =>          'spmtq',

  #Molecular & Cellular Proteomics
  'www.mcponline.org'               =>          'mcprot',

  #Law, Probability and Risk
  'lpr.oupjournals.org'               =>          'lawprj',

  #International Regional Science Review
  'irx.sagepub.com'               =>          'spirx',

  #Western Journal of Nursing Research
  'wjn.sagepub.com'               =>          'spwjn',

  #Journal of Biological Rhythms
  'jbr.sagepub.com'               =>          'spjbr',

  #The European Journal of Public Health
  'eurpub.oupjournals.org'               =>          'eurpub',

  #Journal of Management Education
  'jme.sagepub.com'               =>          'spjme',

  #Crime, Media, Culture
  'cmc.sagepub.com'               =>          'spcmc',

  #Advances in Physiology Education
  'advan.physiology.org'               =>          'ajpadvan',

  #European Journal of Social Theory
  'est.sagepub.com'               =>          'spest',

  #Journal of Andrology
  'www.andrologyjournal.org'               =>          'jandrol',

  #Journal of Semantics
  'jos.oupjournals.org'               =>          'semant',

  #Health Informatics Journal
  'jhi.sagepub.com'               =>          'spjhi',

  #Philosophy & Social Criticism
  'psc.sagepub.com'               =>          'sppsc',

  #Journal of Geriatric Psychiatry and Neurology
  'jgp.sagepub.com'               =>          'spjgp',

  #Medical Decision Making
  'mdm.sagepub.com'               =>          'spmdm',

  #International Journal of Epidemiology
  'ije.oupjournals.org'               =>          'intjepid',

  #International Journal of Public Opinion Research
  'ijpor.oupjournals.org'               =>          'intpor',

  #Continuing Education in Anaesthesia, Critical Care & Pain
  'ceaccp.oupjournals.org'               =>          'bjarev',

  #Journal of the International Association of Physicians in AIDS Care (JIAPAC)
  'jia.sagepub.com'               =>          'spjia',

  #Dentomaxillofacial Radiology
  'dmfr.birjournals.org'               =>          'dmfr',

  #Human Molecular Genetics
  'hmg.oupjournals.org'               =>          'hmg',

  #Journal of Pentecostal Theology
  'jpt.sagepub.com'               =>          'spjpt',

  #Science Communication
  'scx.sagepub.com'               =>          'spscx',

  #Advances in Dental Research
  'adr.iadrjournals.org'               =>          'adent',

  #American Mineralogist
  'ammin.geoscienceworld.org'               =>          'gsammin',

  #Human Reproduction Update
  'humupd.oupjournals.org'               =>          'humupd',

  #Archives of Family Medicine
  'archfami.ama-assn.org'               =>          'archfami',

  #Parliamentary Affairs
  'pa.oupjournals.org'               =>          'parlij',

  #Journal of Biochemistry
  'jb.oupjournals.org'               =>          'jbiochem',

  #Diabetes Care
  'care.diabetesjournals.org'               =>          'diacare',

  #Carcinogenesis
  'carcin.oupjournals.org'               =>          'carcin',

  #Comparative Political Studies
  'cps.sagepub.com'               =>          'spcps',

  #East European Politics and Societies
  'eep.sagepub.com'               =>          'speep',

  #European Journal of Cultural Studies
  'ecs.sagepub.com'               =>          'specs',

  #PNAS
  'www.pnas.org'               =>          'pnas',

  #Active Learning in Higher Education
  'alh.sagepub.com'               =>          'spalh',

  #Economic and Industrial Democracy
  'eid.sagepub.com'               =>          'speid',

  #AAPG Bulletin
  'aapgbull.geoscienceworld.org'               =>          'gsaapgbull',

  #CA: A Cancer Journal for Clinicians
  'caonline.amcancersoc.org'               =>          'canjclin',

  #Journal of Obstetric, Gynecologic, and Neonatal Nursing
  'jognn.awhonn.org'               =>          'jognn',

  #Agronomy Journal
  'agron.scijournals.org'               =>          'agrojnl',

  #Journal of Applied Gerontology
  'jag.sagepub.com'               =>          'spjag',

  #Psychosomatics
  'psy.psychiatryonline.org'               =>          'psy',

  #China Information
  'cin.sagepub.com'               =>          'spcin',

  #Bulletin of Canadian Petroleum Geology
  'bcpg.geoscienceworld.org'               =>          'gscpgbull',

  #International Relations of the Asia-Pacific
  'irap.oupjournals.org'               =>          'irap',

  #Action Research
  'arj.sagepub.com'               =>          'sparj',

  #Blood
  'www.bloodjournal.org'               =>          'bloodjournal',

  #Comparative American Studies
  'cas.sagepub.com'               =>          'spcas',

  #Environmental and Engineering Geoscience
  'eeg.geoscienceworld.org'               =>          'gseegeosci',

  #Molecular Biology of the Cell
  'www.molbiolcell.org'               =>          'molbiolcell',

  #International Journal of Comparative Sociology
  'cos.sagepub.com'               =>          'spcos',

  #International Small Business Journal
  'isb.sagepub.com'               =>          'spisb',

  #Sociology
  'soc.sagepub.com'               =>          'spsoc',

  #Journal of Human Values
  'jhv.sagepub.com'               =>          'spjhv',

  #Archives of Otolaryngology - Head and Neck Surgery
  'archotol.ama-assn.org'               =>          'archotol',

  #Time & Society
  'tas.sagepub.com'               =>          'sptas',

  #Sexualities
  'sexualities.sagepub.com'               =>          'spsex',

  #Contributions to Indian Sociology
  'cis.sagepub.com'               =>          'spcis',

  #American Journal of Neuroradiology
  'www.ajnr.org'               =>          'ajnr',

  #Journal of Vascular and Interventional Radiology
  'www.jvir.org'               =>          'jvascir',

  #Emergency Medicine Journal
  'emj.bmjjournals.com'               =>          'emermed',

  #Work, Employment & Society
  'wes.sagepub.com'               =>          'spwes',

  #The Annals of Family Medicine
  'www.annfammed.org'               =>          'annalsfm',

  #Radiology
  'radiology.rsnajnls.org'               =>          'radiology',

  #Physiological Genomics
  'physiolgenomics.physiology.org'               =>          'physiolgenomics',

  #Group Processes & Intergroup Relations
  'gpi.sagepub.com'               =>          'spgpi',

  #Journal of Molluscan Studies
  'mollus.oupjournals.org'               =>          'mollus',

  #Global Social Policy
  'gsp.sagepub.com'               =>          'spgsp',

  #Journal of the National Cancer Institute
  'jncicancerspectrum.oupjournals.org'               =>          'jnci',

  #Oxford Economic Papers
  'oep.oupjournals.org'               =>          'oxepap',

  #Stroke
  'stroke.ahajournals.org'               =>          'strokeaha',

  #School Psychology International
  'spi.sagepub.com'               =>          'spspi',

  #Cultural Studies <=> Critical Methodologies
  'csc.sagepub.com'               =>          'spcsc',

  #American Journal of Respiratory and Critical Care Medicine
  'www.ajrccm.org'               =>          'ajrccm',

  #Feminism & Psychology
  'fap.sagepub.com'               =>          'spfap',

  #Communication Theory
  'ct.oupjournals.org'               =>          'comthe',

  #Space and Culture
  'sac.sagepub.com'               =>          'spsac',

  #Journal of the American Academy of Psychiatry and the Law Online
  'www.jaapl.org'               =>          'jaapl',

  #Annals of Internal Medicine
  'www.annals.org'               =>          'annintmed',

  #American Behavioral Scientist
  'abs.sagepub.com'               =>          'spabs',

  #Organization Studies
  'oss.sagepub.com'               =>          'sposs',

  #Journal of Cross-Cultural Psychology
  'jcc.sagepub.com'               =>          'spjcc',

  #Social Studies of Science
  'sss.sagepub.com'               =>          'spsss',

  #Current Sociology
  'csi.sagepub.com'               =>          'spcsi',

  #Ecclesiology
  'ecc.sagepub.com'               =>          'specc',

  #Journal of the Royal Musical Association
  'jrma.oupjournals.org'               =>          'roymus',

  #ASH Education Program Book
  'www.asheducationbook.org'               =>          'bloodbook',

  #Leadership
  'lea.sagepub.com'               =>          'splea',

  #NeuroRx
  'www.neurorx.org'               =>          'neurorx',

  #The Quarterly Journal of Mechanics and Applied Mathematics
  'qjmam.oupjournals.org'               =>          'qjmamj',

  #FEBS Journal
  'content.febsjournal.org'               =>          'ejbiochem',

  #Occupational Medicine
  'occmed.oupjournals.org'               =>          'occumed',

  #Journal of Cognitive Neuroscience
  'jocn.mitpress.org'               =>          'jocn',

  #Journalism
  'jou.sagepub.com'               =>          'spjou',

  #Journal of Studies in International Education
  'jsi.sagepub.com'               =>          'spjsi',

  #Cooperation and Conflict
  'cac.sagepub.com'               =>          'spcac',

  #Journal of Cellular Plastics
  'cel.sagepub.com'               =>          'spcel',

  #Behavioral Ecology
  'beheco.oupjournals.org'               =>          'beheco',

  #Assessment
  'asm.sagepub.com'               =>          'spasm',

  #The Annals of Thoracic Surgery
  'ats.ctsnetjournals.org'               =>          'annts',

  #Archives of Facial Plastic Surgery
  'archfaci.ama-assn.org'               =>          'archfaci',

  #The Journal of Lipid Research
  'www.jlr.org'               =>          'jlr',

  #Journal of Reinforced Plastics and Composites
  'jrp.sagepub.com'               =>          'spjrp',

  #Pediatrics
  'pediatrics.aappublications.org'               =>          'pediatrics',

  #European Journal of International Law
  'ejil.oupjournals.org'               =>          'ejilaw',

  #Journal of Economic Geography
  'joeg.oupjournals.org'               =>          'jnlecg',

  #Journal of Dairy Science
  'jds.fass.org'               =>          'dairysci',

  #Bulletin de la Société Géologique de France
  'bsgf.geoscienceworld.org'               =>          'gssgfbull',

  #Economic Inquiry
  'ei.oupjournals.org'               =>          'ecoinq',

  #Molecular Endocrinology
  'mend.endojournals.org'               =>          'mend',

  #IMA Journal of Numerical Analysis
  'imanum.oupjournals.org'               =>          'imanum',

  #Journal of Medical Genetics
  'jmg.bmjjournals.com'               =>          'jmedgenet',

  #Journal of the American Academy of Religion
  'jaar.oupjournals.org'               =>          'jaarel',

  #Theology and Sexuality
  'tse.sagepub.com'               =>          'sptse',

  #The Computer Journal
  'comjnl.oupjournals.org'               =>          'comjnl',

  #British Journal of Radiology
  'bjr.birjournals.org'               =>          'bjradio',

  #Simulation & Gaming
  'sag.sagepub.com'               =>          'spsag',

  #American Journal of Botany
  'www.amjbot.org'               =>          'amjbot',

  #Journal of Cell Science
  'jcs.biologists.org'               =>          'joces',

  #Security Dialogue
  'sdi.sagepub.com'               =>          'spsdi',

  #International Journal of Social Psychiatry
  'isp.sagepub.com'               =>          'spisp',

  #Affilia
  'aff.sagepub.com'               =>          'spaff',

  #Journal of Business Communication
  'job.sagepub.com'               =>          'spjob',

  #The Biological Bulletin
  'www.biolbull.org'               =>          'biolbull',

  #The FASEB Journal
  'www.fasebj.org'               =>          'fasebj',

  #Cultural Dynamics
  'cdy.sagepub.com'               =>          'spcdy',

  #Community Development Journal
  'cdj.oupjournals.org'               =>          'cdj',

  #The Journal of Cell Biology
  'www.jcb.org'               =>          'jcb',

  #Experimental Physiology
  'ep.physoc.org'               =>          'expphysiol',

  #Thorax
  'thorax.bmjjournals.com'               =>          'thoraxjnl',

  #American Law and Economics Review
  'aler.oupjournals.org'               =>          'aler',
  'aler.oxfordjournals.org'		=>	   'aler',

  #Microbiology
  'mic.sgmjournals.org'               =>          'mic',

  #Journal of Transcultural Nursing
  'tcn.sagepub.com'               =>          'sptcn',

  #Pediatric Research
  'www.pedresearch.org'               =>          'pedresearch',

  #Molecular Cancer Therapeutics
  'mct.aacrjournals.org'               =>          'molcanther',

  #Clinical Diabetes
  'clinical.diabetesjournals.org'               =>          'diaclin',

  #Bulletin of the Seismological Society of America
  'bssa.geoscienceworld.org'               =>          'gsssabull',

  #The Expository Times
  'ext.sagepub.com'               =>          'spext',

  #British Medical Bulletin
  'bmb.oupjournals.org'               =>          'bmbull',

  #History of the Human Sciences
  'hhs.sagepub.com'               =>          'sphhs',

  #History of Psychiatry
  'hpy.sagepub.com'               =>          'sphpy',

  #The Shock and Vibration Digest
  'svd.sagepub.com'               =>          'spsvd',

  #International Journal of Offender Therapy and Comparative Criminology
  'ijo.sagepub.com'               =>          'spijo',

  #Obesity Research
  'www.obesityresearch.org'               =>          'obesityres',

  #Behavioral and Cognitive Neuroscience Reviews
  'bcn.sagepub.com'               =>          'spbcn',

  #Annals of the Rheumatic Diseases
  'ard.bmjjournals.com'               =>          'annrheumdis',

  #Journal of Contemporary Criminal Justice
  'ccj.sagepub.com'               =>          'spccj',

  #Sociological Methods & Research
  'smr.sagepub.com'               =>          'spsmr',

  #Experimental Mechanics
  'exm.sagepub.com'               =>          'spexm',

  #Evaluation & the Health Professions
  'ehp.sagepub.com'               =>          'spehp',

  #South Asia Economic Journal
  'sae.sagepub.com'               =>          'spsae',

  #French History
  'fh.oupjournals.org'               =>          'french',

  #Journal of Interpersonal Violence
  'jiv.sagepub.com'               =>          'spjiv',

  #Media, Culture & Society
  'mcs.sagepub.com'               =>          'spmcs',

  #Urban Affairs Review
  'uar.sagepub.com'               =>          'spuar',

  #Endocrine-Related Cancer
  'erc.endocrinology-journals.org'               =>          'erc',

  #Adaptive Behavior
  'adb.sagepub.com'               =>          'spadb',

  #Qualitative Social Work
  'qsw.sagepub.com'               =>          'spqsw',

  #Journal of Classical Sociology
  'jcs.sagepub.com'               =>          'spjcs',

  #Development
  'dev.biologists.org'               =>          'develop',

  #Qualitative Research
  'qrj.sagepub.com'               =>          'spqrj',

  #Journal of Animal Science
  'jas.fass.org'               =>          'animalsci',

  #The Family Journal
  'tfj.sagepub.com'               =>          'sptfj',

  #Nucleic Acids Symposium Series
  'nass.oupjournals.org'               =>          'nass',

  #Journal of Humanistic Psychology
  'jhp.sagepub.com'               =>          'spjhp',

  #European Journal of International Relations
  'ejt.sagepub.com'               =>          'spejt',

  #The Journal of Early Adolescence
  'jea.sagepub.com'               =>          'spjea',

  #Theory and Research in Education
  'tre.sagepub.com'               =>          'sptre',

  #Journal of Nutrition
  'www.nutrition.org'               =>          'nutrition',

  #Journal of Law, Economics, and Organization
  'jleo.oupjournals.org'               =>          'jleo',

  #Journal of International Economic Law
  'jiel.oupjournals.org'               =>          'jielaw',

  #Journal of Material Culture
  'mcu.sagepub.com'               =>          'spmcu',

  #Journal of Health Management
  'jhm.sagepub.com'               =>          'spjhm',

  #Quality and Safety in Health Care
  'qhc.bmjjournals.com'               =>          'qhc',

  #Home Health Care Management & Practice
  'hhc.sagepub.com'               =>          'sphhc',

  #International Review of Administrative Sciences
  'ras.sagepub.com'               =>          'spras',

  #Race & Class
  'rac.sagepub.com'               =>          'sprac',

  #Political Theory
  'ptx.sagepub.com'               =>          'spptx',

  #Journal of Competition Law and Economics
  'jcle.oupjournals.org'               =>          'jcle',

  #Journal of Intellectual Disabilities
  'jid.sagepub.com'               =>          'spjld',

  #Exploration and Mining Geology
  'emg.geoscienceworld.org'               =>          'gsemg',

  #Cell Growth & Differentiation
  'cgd.aacrjournals.org'               =>          'cellgd',

  #Archives of Dermatology
  'archderm.ama-assn.org'               =>          'archderm',

  #Journal of Aging and Health
  'jah.sagepub.com'               =>          'spjah',

  #Academic Emergency Medicine
  'www.aemj.org'               =>          'aemj',

  #The Journal of Immunology
  'www.jimmunol.org'               =>          'jimmunol',

  #Twentieth Century British History
  'tcbh.oupjournals.org'               =>          'tweceb',

  #The American Journal of Tropical Medicine and Hygiene
  'www.ajtmh.org'               =>          'tropmed',

  #Politics, Philosophy & Economics
  'ppe.sagepub.com'               =>          'spppe',

  #The Counseling Psychologist
  'tcp.sagepub.com'               =>          'sptcp',

  #Journal of Family Issues
  'jfi.sagepub.com'               =>          'spjfi',

  #Applied Psychological Measurement
  'apm.sagepub.com'               =>          'spapm',

  #Journal of Service Research
  'jsr.sagepub.com'               =>          'spjsr',

  #Journal of Family Nursing
  'jfn.sagepub.com'               =>          'spjfn',

  #European Physical Education Review
  'epe.sagepub.com'               =>          'spepe',

  #Aramaic Studies
  'ars.sagepub.com'               =>          'spars',

  #Journal of Public Administration Research and Theory
  'jpart.oupjournals.org'               =>          'jpart',

  #Neural Computation
  'neco.mitpress.org'               =>          'neco',

  #Management Communication Quarterly
  'mcq.sagepub.com'               =>          'spmcq',

  #Journal of Bone & Joint Surgery, British Volume
  'www.jbjs.org.uk'               =>          'jbjsbr',

  #Health:
  'hea.sagepub.com'               =>          'sphea',

  #Thesis Eleven
  'the.sagepub.com'               =>          'spthe',

  #Advances in Psychiatric Treatment
  'apt.rcpsych.org'               =>          'aptrcpsych',

  #Indoor and Built Environment
  'ibe.sagepub.com'               =>          'spibe',

  #Journal of Career Assessment
  'jca.sagepub.com'               =>          'spjca',

  #Bioinformatics
  'bioinformatics.oupjournals.org'               =>          'bioinfo',

  #Journal of Urban Health: Bulletin of the New York Academy of Medicine
  'jurban.oupjournals.org'               =>          'jurban',

  #Criminal Justice
  'crj.sagepub.com'               =>          'spcrj',

  #Police Quarterly
  'pqx.sagepub.com'               =>          'sppqx',

  #Journal of Business and Technical Communication
  'jbt.sagepub.com'               =>          'spjbt',

  #Culture & Psychology
  'cap.sagepub.com'               =>          'spcap',

  #The Library
  'library.oupjournals.org'               =>          'libraj',

  #Rocky Mountain Geology
  'rmg.geoscienceworld.org'               =>          'gsrocky',

  #Urban Education
  'uex.sagepub.com'               =>          'spuex',

  #The Annals of Pharmacotherapy
  'www.theannals.com'               =>          'pharmther',

  #Journal of Theoretical Politics
  'jtp.sagepub.com'               =>          'spjtp',

  #National Institute Economic Review
  'ner.sagepub.com'               =>          'spner',

  #Journal of Black Psychology
  'jbp.sagepub.com'               =>          'spjbp',

  #The Journal of Clinical Pharmacology
  'jcp.sagepub.com'               =>          'jclinpharm',

  #The American Review of Public Administration
  'arp.sagepub.com'               =>          'sparp',

  #Journal of the American Medical Informatics Association
  'www.jamia.org'               =>          'jamia',

  #Journal of Psychopharmacology
  'jop.sagepub.com'               =>          'spjop',

  #Journal of Molecular Endocrinology
  'jme.endocrinology-journals.org'               =>          'jme',

  #Political Analysis
  'pan.oupjournals.org'               =>          'polana',

  #Journal of Thermal Envelope and Building Science
  'jen.sagepub.com'               =>          'spjen',

  #Genes to Cells
  'www.genestocellsonline.org'               =>          'genescells',

  #Journal of Intensive Care Medicine
  'jic.sagepub.com'               =>          'spjic',

  #International Journal of Refugee Law
  'ijrl.oupjournals.org'               =>          'reflaw',

  #Critical Reviews in Oral Biology & Medicine
  'crobm.iadrjournals.org'               =>          'crobm',

  #Journal of the American Society of Nephrology
  'www.jasn.org'               =>          'jnephrol',

  #Psychology & Developing Societies
  'pds.sagepub.com'               =>          'sppds',

  #European Heart Journal
  'eurheartj.oupjournals.org'               =>          'ehj',

  #Enterprise and Society
  'es.oupjournals.org'               =>          'entsoc',

  #Child Maltreatment
  'cmx.sagepub.com'               =>          'spcmx',

  #American Journal of Physiology - Lung Cellular and Molecular Physiology
  'ajplung.physiology.org'               =>          'ajplung',

  #Group Analysis
  'gaq.sagepub.com'               =>          'spgaq',

  #Journal of Family History
  'jfh.sagepub.com'               =>          'spjfh',

  #Contributions to Political Economy
  'cpe.oupjournals.org'               =>          'conpec',

  #Industrial Law Journal
  'ilj.oupjournals.org'               =>          'indlaw',

  #Clays and Clay Minerals
  'ccm.geoscienceworld.org'               =>          'gsccm',

  #Annals of Clinical & Laboratory Science
  'www.annclinlabsci.org'               =>          'acls',

  #International Criminal Justice Review
  'icj.sagepub.com'               =>          'spicj',

  #The Oncologist
  'theoncologist.alphamedpress.org'               =>          'theoncologist',

  #Journal of Molecular Diagnostics
  'jmd.amjpathol.org'               =>          'moldiag',

  #The American Journal of Sports Medicine
  'journal.ajsm.org'               =>          'amjsports',

  #Science's STKE
  'stke.sciencemag.org'               =>          'sigtrans',

  #South African Journal of Geology
  'sajg.geoscienceworld.org'               =>          'gssajg',

  #Age and Ageing
  'ageing.oupjournals.org'               =>          'ageing',

  #Nonprofit and Voluntary Sector Quarterly
  'nvs.sagepub.com'               =>          'spnvs',

  #Canadian Medical Association Journal
  'www.cmaj.ca'               =>          'cmaj',

  #Canadian Journal of Anesthesia
  'www.cja-jca.org'               =>          'canjana',

  #Criminal Justice Review
  'cjr.sagepub.com'               =>          'spcjr',

  #Journal of Deaf Studies and Deaf Education
  'deafed.oupjournals.org'               =>          'deafed',

  #Journal of Clinical Pathology
  'jcp.bmjjournals.com'               =>          'jclinpath',

  #Journal of Biomaterials Applications
  'jba.sagepub.com'               =>          'spjba',

  #Journal of Dental Education
  'www.jdentaled.org'               =>          'jde',

  #Clinical and Diagnostic Laboratory Immunology
  'cdli.asm.org'               =>          'cdli',

  #Cross-Cultural Research
  'ccr.sagepub.com'               =>          'spccr',

  #Molecular Biology and Evolution
  'mbe.oupjournals.org'               =>          'molbiolevol',

  #Science, Technology & Human Values
  'sth.sagepub.com'               =>          'spsth',

  #IEICE Transactions on Electronics
  'ietele.oupjournals.org'               =>          'ietele',

  #American Journal of Medical Quality
  'ajm.sagepub.com'               =>          'spajm',

  #The Gerontologist
  'gerontologist.gerontologyjournals.org'               =>          'thegeron',

  #American Journal of Enology and Viticulture
  'www.ajevonline.org'               =>          'ajev',

  #Journal of Nuclear Medicine Technology
  'tech.snmjournals.org'               =>          'jnmt',

  #European Journal of Criminology
  'euc.sagepub.com'               =>          'speuc',

  #Experimental Biology and Medicine
  'www.ebmonline.org'               =>          'psebm',

  #Organization
  'org.sagepub.com'               =>          'sporg',

  #Studies in History
  'sih.sagepub.com'               =>          'spsih',

  #Archives of Neurology
  'archneur.ama-assn.org'               =>          'archneur',

  #Arts and Humanities in Higher Education
  'ahh.sagepub.com'               =>          'spahh',

  #Journal of the American College of Nutrition
  'www.jacn.org'               =>          'jamcnutr',

  #British Journal of Social Work
  'bjsw.oupjournals.org'               =>          'bjsw',

  #Medical Humanities
  'mh.bmjjournals.com'               =>          'medhum',

  #Personality and Social Psychology Bulletin
  'psp.sagepub.com'               =>          'sppsp',

  #Archives of Pediatrics and Adolescent Medicine
  'archpedi.ama-assn.org'               =>          'archpedi',

  #Education and Urban Society
  'eus.sagepub.com'               =>          'speus',

  #Journal of Fire Sciences
  'jfs.sagepub.com'               =>          'spjfs',

  #Learning & Memory
  'www.learnmem.org'               =>          'learnmem',

  #Journal Of Vacation Marketing
  'jvm.sagepub.com'               =>          'spjvm',

  #Molecular Pharmacology
  'molpharm.aspetjournals.org'               =>          'molpharm',

  #Evaluation Review
  'erx.sagepub.com'               =>          'sperx',

  #Genome Research
  'www.genome.org'               =>          'genome',

  #British Journalism Review
  'bjr.sagepub.com'               =>          'spbjr',

  #Global Media and Communication
  'gmc.sagepub.com'               =>          'spgmc',

  #Clinical Cancer Research
  'clincancerres.aacrjournals.org'               =>          'clincanres',

  #Palaios
  'palaios.geoscienceworld.org'               =>          'gspalaios',

  #British Journal of Visual Impairment
  'jvi.sagepub.com'               =>          'spjvi',

  #Psychology of Music
  'pom.sagepub.com'               =>          'sppom',

  #Annals of Occupational Hygiene
  'annhyg.oupjournals.org'               =>          'annhyg',

  #Discourse Studies
  'dis.sagepub.com'               =>          'spdis',

  #Journal of Applied Physiology
  'jap.physiology.org'               =>          'jap',

  #RNA
  'www.rnajournal.org'               =>          'rna',

  #American Journal of Geriatric Psychiatry
  'ajgp.psychiatryonline.org'               =>          'ajgp',

  #Clinical Nursing Research
  'cnr.sagepub.com'               =>          'spcnr',

  #Rheumatology
  'rheumatology.oupjournals.org'               =>          'rheumatology',

  #Public Opinion Quarterly
  'poq.oupjournals.org'               =>          'pubopq',

  #History Workshop Journal
  'hwj.oupjournals.org'               =>          'hiwork',

  #Health Promotion Practice
  'hpp.sagepub.com'               =>          'sphpp',

  #Mathematics and Mechanics of Solids
  'mms.sagepub.com'               =>          'spmms',

  #IMA Journal of Applied Mathematics
  'imamat.oupjournals.org'               =>          'imamat',

  #Brain
  'brain.oupjournals.org'               =>          'brain',

  #American Journal of Evaluation
  'aje.sagepub.com'               =>          'spaje',

  #Clinical Chemistry
  'www.clinchem.org'               =>          'clinchem',

  #The Harvard International Journal of Press/Politics
  'hij.sagepub.com'               =>          'sphij',

  #Eukaryotic Cell
  'ec.asm.org'               =>          'eukcell',

  #Health Affairs
  'content.healthaffairs.org'               =>          'healthaff',

  #European Journal of Archaeology
  'eja.sagepub.com'               =>          'speja',

  #RadioGraphics
  'radiographics.rsnajnls.org'               =>          'radiographics',

  #Academic Medicine
  'www.academicmedicine.org'               =>          'acadmed',

  #Journal of Sports Economics
  'jse.sagepub.com'               =>          'spjse',

  #American Journal of Epidemiology
  'aje.oupjournals.org'               =>          'amjepid',

  #Asian Cardiovascular and Thoracic Annals
  'asianannals.ctsnetjournals.org'               =>          'ascats',

  #Social Compass
  'scp.sagepub.com'               =>          'spscp',

  #Journal of General Virology
  'vir.sgmjournals.org'               =>          'vir',

  #The Leading Edge
  'tle.geoscienceworld.org'               =>          'gsedge',

  #Journal of Refugee Studies
  'jrs.oupjournals.org'               =>          'refuge',

  #Journal of the American Animal Hospital Association
  'www.jaaha.org'               =>          'jaaha',

  #European Sociological Review
  'esr.oupjournals.org'               =>          'eursoj',

  #Educational Management Administration & Leadership
  'ema.sagepub.com'               =>          'spema',

  #Critical Reviews in Biochemistry and Molecular Biology
  'www.crbmb.com'               =>          'crbmb',

  #American Journal Of Pathology
  'ajp.amjpathol.org'               =>          'amjpathol',

  #First Language
  'fla.sagepub.com'               =>          'spfla',

  #RELC Journal
  'rel.sagepub.com'               =>          'sprel',

  #American Journal of Physiology - Regulatory, Integrative and Comparative Physiology
  'ajpregu.physiology.org'               =>          'ajpregu',

  #Currents in Biblical Research
  'cbi.sagepub.com'               =>          'spcbi',

  #Biological Research For Nursing
  'brn.sagepub.com'               =>          'spbrn',

  #Logic Journal of IGPL
  'jigpal.oupjournals.org'               =>          'igpl',

  #Human Communication Research
  'hcr.oupjournals.org'               =>          'humcom',

  #Hispanic Journal of Behavioral Sciences
  'hjb.sagepub.com'               =>          'sphjb',

  #American Journal of Physiology -- Legacy Content
  'ajplegacy.physiology.org'               =>          'ajplegacy',

  #Educational Administration Quarterly
  'eaq.sagepub.com'               =>          'speaq',

  #International Journal of Music Education
  'ijm.sagepub.com'               =>          'spijm',

  #Food Science and Technology International
  'fst.sagepub.com'               =>          'spfst',

  #Journal of Tropical Pediatrics
  'tropej.oupjournals.org'               =>          'tropej',

  #Neurology
  'www.neurology.org'               =>          'neurology',

  #Diabetes Spectrum
  'spectrum.diabetesjournals.org'               =>          'diaspect',

  #Journal of Human Lactation
  'jhl.sagepub.com'               =>          'spjhl',

  #Japanese Journal of Clinical Oncology
  'jjco.oupjournals.org'               =>          'jjco',

  #Journal of Emerging Market Finance
  'emf.sagepub.com'               =>          'spemf',

  #Journal of Vibration and Control
  'jvc.sagepub.com'               =>          'spjvc',

  #Annals of the New York Academy of Sciences
  'www.annalsnyas.org'               =>          'anny',

  #International Relations
  'ire.sagepub.com'               =>          'spire',

  #Men and Masculinities
  'jmm.sagepub.com'               =>          'spjmm',

  #Journal of Information Science
  'jis.sagepub.com'               =>          'spjis',

  #Oxford Art Journal
  'oaj.oupjournals.org'               =>          'oxartj',

  #Journal of Petrology
  'petrology.oupjournals.org'               =>          'petrology',

  #International Journal of Damage Mechanics
  'ijd.sagepub.com'               =>          'spijd',

  #Literature and Theology
  'litthe.oupjournals.org'               =>          'litthe',

  #South Asia Research
  'sar.sagepub.com'               =>          'spsar',

  #Social History of Medicine
  'shm.oupjournals.org'               =>          'sochis',

  #Cambridge Journal of Economics
  'cje.oupjournals.org'               =>          'cameco',

  #Journal of Conflict and Security Law
  'jcsl.oupjournals.org'               =>          'jconsl',

  #Molecular Interventions
  'molinterv.aspetjournals.org'               =>          'molint',

  #Feminist Theology
  'fth.sagepub.com'               =>          'spfth',

  #Journal of the American Psychiatric Nurses Association
  'jap.sagepub.com'               =>          'spjap',

  #Medical Care Research and Review
  'mcr.sagepub.com'               =>          'spmcr',

  #The Neuroscientist
  'nro.sagepub.com'               =>          'spnro',

  #Journal of International Criminal Justice
  'jicj.oupjournals.org'               =>          'jicjus',

  #Tobacco Control
  'tc.bmjjournals.com'               =>          'tobaccocontrol',

  #Journal of Pediatric Psychology
  'jpepsy.oupjournals.org'               =>          'jpepsy',

  #Brief Treatment and Crisis Intervention
  'brief-treatment.oupjournals.org'               =>          'btcint',

  #Academic Psychiatry
  'ap.psychiatryonline.org'               =>          'ap',

  #Politics & Society
  'pas.sagepub.com'               =>          'sppas',

  #The British Journal of Aesthetics
  'bjaesthetics.oupjournals.org'               =>          'aesthj',

  #New Media & Society
  'nms.sagepub.com'               =>          'spnms',

  #Adult Education Quarterly
  'aeq.sagepub.com'               =>          'spaeq',

  #Punishment & Society
  'pun.sagepub.com'               =>          'sppun',

  #Planning Theory
  'plt.sagepub.com'               =>          'spplt',

  #Journal of Neurology, Neurosurgery & Psychiatry
  'jnnp.bmjjournals.com'               =>          'jnnp',

  #Public Works Management & Policy
  'pwm.sagepub.com'               =>          'sppwm',

  #Journal of Financial Econometrics
  'jfec.oupjournals.org'               =>          'jfinec',

  #Journal of Experimental Biology
  'jeb.biologists.org'               =>          'jexbio',

  #Journal of Logic and Computation
  'logcom.oupjournals.org'               =>          'logcom',

  #The British Journal of Psychiatry
  'bjp.rcpsych.org'               =>          'bjprcpsych',

  #Journal of Plankton Research
  'plankt.oupjournals.org'               =>          'plankt',

  #Journal of Transformative Education
  'jtd.sagepub.com'               =>          'spjtd',

  #Biometrika
  'biomet.oupjournals.org'               =>          'biomet',

  #American Journal of Roentgenology
  'www.ajronline.org'               =>          'ajronline',

  #Circulation Research
  'circres.ahajournals.org'               =>          'circresaha',

  #Journal of Diagnostic Medical Sonography
  'jdm.sagepub.com'               =>          'spjdm',

  #Social Science Information
  'ssi.sagepub.com'               =>          'spssi',

  #International Journal of Systematic and Evolutionary Microbiology
  'ijs.sgmjournals.org'               =>          'ijs',

  #British Journal of Anaesthesia
  'bja.oupjournals.org'               =>          'brjana',

  #Journal of Biomolecular Screening
  'jbx.sagepub.com'               =>          'spjbx',

  #Organizational Research Methods
  'orm.sagepub.com'               =>          'sporm',

  #Journal of Ultrasound in Medicine
  'www.jultrasoundmed.org'               =>          'ultra',

  #Annals of Botany
  'aob.oupjournals.org'               =>          'annbot',

  #NCP- Nutrition in Clinical Practice
  'ncp.aspenjournals.org'               =>          'ncp',

  #Body & Society
  'bod.sagepub.com'               =>          'spbod',

  #International Journal of Law, Policy and the Family
  'lawfam.oupjournals.org'               =>          'lawfam',

  #Diabetes
  'diabetes.diabetesjournals.org'               =>          'diabetes',

  #Journal of Early Childhood Literacy
  'ecl.sagepub.com'               =>          'specl',

  #Organization & Environment
  'oae.sagepub.com'               =>          'spoae',

  #Radiation Protection Dosimetry
  'rpd.oupjournals.org'               =>          'rpd',

  #The Journal of the American Board of Family Practice
  'www.jabfp.org'               =>          'jabfp',

  #Heart
  'heart.bmjjournals.com'               =>          'heartjnl',

  #Journal of Elastomers and Plastics
  'jep.sagepub.com'               =>          'spjep',

  #Ethnography
  'eth.sagepub.com'               =>          'speth',

  #Information Development
  'idv.sagepub.com'               =>          'spidv',

  #Soil Science Society of America Journal
  'soil.scijournals.org'               =>          'soilsci',

  #Journal of Biological Chemistry
  'www.jbc.org'               =>          'jbc',

  #Journal of Adolescent Research
  'jar.sagepub.com'               =>          'spjar',

  #Transcultural Psychiatry
  'tps.sagepub.com'               =>          'sptps',

  #Journal of African Economies
  'jae.oupjournals.org'               =>          'jafeco',

  #Educational and Psychological Measurement
  'epm.sagepub.com'               =>          'spepm',

  #Journal of Contemporary History
  'jch.sagepub.com'               =>          'spjch',

  #Policy, Politics, & Nursing Practice
  'ppn.sagepub.com'               =>          'spppn',

  #European History Quarterly
  'ehq.sagepub.com'               =>          'spehq',

  #Journal of Experimental Botany
  'jxb.oupjournals.org'               =>          'jexbot',

  #Health Policy and Planning
  'heapol.oupjournals.org'               =>          'heapol',

  #International Immunology
  'intimm.oupjournals.org'               =>          'intimm',

  #American Politics Research
  'apr.sagepub.com'               =>          'spapr',

  #ITNOW
  'itnow.oupjournals.org'               =>          'combul',

  #Journal of Fire Protection Engineering
  'jfe.sagepub.com'               =>          'spjfe',

  #Music and Letters
  'ml.oupjournals.org'               =>          'musicj',

  #Discourse & Society
  'das.sagepub.com'               =>          'spdas',

  #Indian Economic & Social History Review
  'ier.sagepub.com'               =>          'spier',

  #Modern China
  'mcx.sagepub.com'               =>          'spmcx',

  #Journal of the History of Collections
  'jhc.oupjournals.org'               =>          'hiscol',

  #Applied and Environmental Microbiology
  'aem.asm.org'               =>          'aem',

  #Pharmacological Reviews
  'pharmrev.aspetjournals.org'               =>          'pharmrev',

  #Journal of Neuropsychiatry and Clinical Neurosciences
  'neuro.psychiatryonline.org'               =>          'neuropsych',

  #Anesthesia & Analgesia
  'www.anesthesia-analgesia.org'               =>          'anesthanalg',

  #The Journal of Environment & Development
  'jed.sagepub.com'               =>          'spjed',

  #Asian Journal of Management Cases
  'ajc.sagepub.com'               =>          'spajc',

  #Journal of Heredity
  'jhered.oupjournals.org'               =>          'jhered',

  #Nucleic Acids Research
  'nar.oupjournals.org'               =>          'nar',

  #Gut
  'gut.bmjjournals.com'               =>          'gutjnl',

  #Journal of Research in International Education
  'jri.sagepub.com'               =>          'spjri',

  #Literary and Linguistic Computing
  'llc.oupjournals.org'               =>          'litlin',

  #Multimedia Manual of Cardio-thoracic Surgery
  'mmcts.ctsnetjournals.org'               =>          'mmctsman',

  #Interactive CardioVascular and Thoracic Surgery
  'icvts.ctsnetjournals.org'               =>          'icvts',

  #Journal of Social Work
  'jsw.sagepub.com'               =>          'spjsw',

  #Journal of Islamic Studies
  'jis.oupjournals.org'               =>          'islamj',

  #Journal of Pharmacology and Experimental Therapeutics
  'jpet.aspetjournals.org'               =>          'jpet',

  #Communication Research
  'crx.sagepub.com'               =>          'spcrx',

  #Journal of Management
  'jom.sagepub.com'               =>          'spjom',

  #Research on Aging
  'roa.sagepub.com'               =>          'sproa',

  #In Practice
  'inpractice.bvapublications.com'               =>          'ipmag',

  #Neurorehabilitation and Neural Repair
  'nnr.sagepub.com'               =>          'spnnr',

  #Hypertension
  'hyper.ahajournals.org'               =>          'hypertensionaha',

  #European Journal of Political Theory
  'ept.sagepub.com'               =>          'spept',

  #IFLA Journal
  'ifl.sagepub.com'               =>          'spifl',

  #Journal of Sport and Social Issues
  'jss.sagepub.com'               =>          'spjss',

  #Drug Metabolism and Disposition
  'dmd.aspetjournals.org'               =>          'dmd',

  #Journal for the Study of the Pseudepigrapha
  'jsp.sagepub.com'               =>          'spjsp',

  #European Journal of Cardio-Thoracic Surgery
  'ejcts.ctsnetjournals.org'               =>          'ejcts',

  #Veterinary Pathology Online
  'www.vetpathology.org'               =>          'vetpath',

  #Journal of Dental Research
  'jdr.iadrjournals.org'               =>          'jdent',

  #Philosophy of the Social Sciences
  'pos.sagepub.com'               =>          'sppos',

  #Social & Legal Studies
  'sls.sagepub.com'               =>          'spsls',

  #Health Promotion International
  'heapro.oupjournals.org'               =>          'heapro',

  #Journal of Environmental Quality
  'jeq.scijournals.org'               =>          'joenq',

  #Clinical Case Studies
  'ccs.sagepub.com'               =>          'spccs',

  #Journal of Neuroscience
  'www.jneurosci.org'               =>          'jneuro',

  #Micropaleontology
  'micropal.geoscienceworld.org'               =>          'gsmicropal',

  #--- Science --- needs authorization to get citation data
  'sciencemag.org'					=> {RIS_PREFIX => 'sci', ACCT_TYPE => 'SCIENCE'},


#Original manually identified mappings:

##--- OUP JOURNALS ---
#		# Bioinformatics
#   	'bioinformatics.oupjournals.org' 	=> 'bioinfo',
#		# Nucleic Acids Research
#  	'nar.oupjournals.org'				=> 'nar',
#		# Brain 
#  	'brain.oupjournals.org'				=> 'brain',
#		# JNCI Cancer Spectrum 
#  	'jncicancerspectrum.oupjournals.org'	=> 'jnci',
#		# The Journal of Biochemistry
#  	'jb.oupjournals.org'				=> 'jbiochem',
#		# Cerebral Cortex
#  	'cercor.oupjournals.org'			=> 'cercor',
#		# Molecular Biology and Evolution
#  	'mbe.oupjournals.org'				=> 'molbiolevol',
##--- PNAS ---
#  	'pnas.org'							=> 'pnas',
##--- Science --- (doesn't work for RIS yet)
#  	'sciencemag.org'					=> 'sci',
);
my ($hRef) = \%Bibliotech::CitationSoure::Highwire::HostTable::Hosts;

sub defined {
  my ($host) = @_;
  return 1 if defined($hRef->{$host}) || defined($hRef->{_without_www($host)});
  return 0;
}

sub getRISPrefix {
  my ($host) = @_;
  return $hRef->{$host} if $hRef->{$host};
  return $hRef->{_without_www($host)};
}

sub _without_www {
  local $_ = shift;
  s/^www.//;
  return $_;
}

1;
__END__
