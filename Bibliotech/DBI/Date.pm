package Bibliotech::Date;
use strict;
use base ('DateTime', 'Bibliotech::DBI');
use DateTime::Incomplete;
use DateTime::Format::MySQL;
use DateTime::Format::ISO8601;
use Date::Parse ();
use Bibliotech::Util;

our $TIME_ZONE_ON_DB_HOST = Bibliotech::Config->get('TIME_ZONE_ON_DB_HOST') || 'local';
our $TIME_ZONE_PROVIDED   = Bibliotech::Config->get('TIME_ZONE_PROVIDED');

sub _as_datetime_constructor {
  my $class = shift;
  my $dt = DateTime->new(@_);
  return bless $dt, ref $class || $class;
}

sub _as_quick_database_conversion {
  my ($class, $str) = @_;
  my $dt = eval {
    # this will be so common make it the assumed version
    # actually this ::MySQL module is not 100% effective; can't handle zero's and make a DateTime::Incomplete
    DateTime::Format::MySQL->parse_datetime($str);
  };
  return if $@;
  bless $dt, ref $class || $class;
  $dt->mark_time_zone_from_db;
  return $dt;
}

sub _long_parse {
  my ($class, $str, $create) = @_;
  my $self;
  my $complete = 1;
  # handle the contingency that it is not a date from MySQL, or that it contains zero's e.g. (2005-01-00)
  # first remove any leading/trailing spaces
  $str =~ s|^\s+||;
  $str =~ s|\s+$||;
  # convert x's to zero's since we use x's for incomplete dates and x is not valid in any month name:
  $str =~ s|x|0|g;
  eval {
    # handle 'YYYY-MM-DD HH:MM:SS ZONE' and 'YYYY-MM-DDTHH:MM:SSZONE'
    if ($str =~ /^(\d+-\d+-\d+)(([ T])(\d+:\d+:\d+) ?(.*))?$/) {
      my ($date, $more_than_date, $char, $time, $tz) = ($1, $2, $3, $4, $5);
      if ($more_than_date) {
	if ($char eq ' ') {
	  $self = DateTime::Format::MySQL->parse_datetime(join(' ', $date, $time));
	  $self->set_time_zone($tz || $TIME_ZONE_ON_DB_HOST);
	}
	else {  # char is T
	  $self = DateTime::Format::ISO8601->parse_datetime($str);
	}
      }
      else {
	$self = DateTime::Format::MySQL->parse_date($date);
	$self->set_time_zone($TIME_ZONE_ON_DB_HOST);
      }
    }
  };
  if (!$self or $@) {
    eval {
      # handle anything else on God's green earth
      $str =~ s|^(\d{4}/\w*/\w*)/.+$|$1|;  # YYYY/MM/DD/print
      $str =~ s|/+$||;
      $str =~ s|^([a-zA-Z]+)\W*(\d{4})$|$1 0, $2|;  # mmm YYYY
      $str =~ s|^(\d{4})\W*([a-zA-Z]+)$|$2 0, $1|;  # YYYY mmm
      $str =~ s|^(\d{4})\W*([a-zA-Z]+)\W*(\d+)$|$2 $3, $1|;  # YYYY-mmm-DD
      $str =~ s|^([a-zA-Z]+)\W*(\d{1,2})\W*(\d{4})$|$2 $1, $3|;  # mmm-DD-YYYY
      $str =~ s|^(\d{4})\W+(\d+)$|$1-$2-00|;  # YYYY/MM
      $str =~ s|^(\d{4})[-/](\d+)[-/](\d+)$|sprintf('%04d-%02d-%02d', $1, $2, $3)|e;  # YYYY/MM/DD
      my ($second, $minute, $hour, $day, $month, $year, $tz) = Date::Parse::strptime($str);
      $year = undef if $year eq '0000';  # because 1900 comes back as 0 not 0000
      $year += 1900 if defined $year;    # deal with default perl year format
      $month++ if defined $month;        # deal with default perl month format
      $year = undef unless $year > 0;    # 0 and 00
      $month = undef unless $month > 0;  # 0 and 00
      $day = undef unless $day > 0;      # 0 and 00
      $year = int($year) if defined $year;
      $month = int($month) if defined $month;
      $day = int($day) if defined $day;
      $hour = int($hour) if defined $hour;
      $minute = int($minute) if defined $minute;
      $second = int($second) if defined $second;
      my $class = 'DateTime';
      if (defined $year and defined $month and defined $day and defined $hour and defined $minute) {
	$second = 0 if !defined $second;
      }
      else {
	$complete = 0;
	$class .= '::Incomplete';
      }
      $self = $class->new(year => $year, month => $month, day => $day,
			  hour => $hour, minute => $minute, second => $second,
			  time_zone => $tz || $TIME_ZONE_ON_DB_HOST);
      bless $self, 'Bibliotech::Date::Incomplete' if !$complete;
    };
    if ($@) {
      die $@ if $@ =~ /cannot determine/i;  # e.g. Cannot determine local time zone
      die "Invalid date/time: $str ($@)\n" if $create;
      $self = $class->zero;
    }
  }
  return ($self, $complete);
}

sub new {
  my ($class, $str, $create, $self, $complete);
  if (@_ > 3) {
    $class = shift;
    $self = _as_datetime_constructor($class, @_) or return;
    $complete = $self->isa('DateTime::Incomplete') ? 0 : 1;
  }
  else {
    ($class, $str, $create) = @_;
    if ($self = _as_quick_database_conversion($class, $str)) {
      $complete = 1;
    }
    else {
      ($self, $complete) = _long_parse($class, $str, $create);
    }
  }
  bless $self, ref $class || $class if $complete;
  $self->convert_time_zone_to_desired;
  return $self;
}

sub convert_time_zone {
  my ($self, $tz) = @_;
  #print "convert_time_zone: pre:  $self ".$self->time_zone."\n";
  return $self if not defined $tz;
  $self->set_time_zone($tz);
  #print "convert_time_zone: post: $self ".$self->time_zone."\n";
  return $self;
}

sub mark_time_zone_from_db {
  shift->convert_time_zone($TIME_ZONE_ON_DB_HOST);
}

sub convert_time_zone_to_desired {
  shift->convert_time_zone($TIME_ZONE_PROVIDED);
}

sub incomplete {
  0;
}

sub complete {
  !shift->incomplete;
}

# return a string appropriate to send to MySQL - most importantly, set time zone to MySQL operating time zone
sub mysql_format {
  my ($self, $type) = @_;
  my $clone = $self->clone_if_necessary_for_tz($TIME_ZONE_ON_DB_HOST);
  my $func = 'format_'.($type || 'date');
  return DateTime::Format::MySQL->$func($clone);
}

sub mysql_datetime {
  shift->mysql_format('datetime');
}

sub mysql_date {
  shift->mysql_format('date');
}

sub query_format {
  shift->mysql_date(@_);
}

# an alternative to now() that does the same thing but gets the time from the MySQL daemon
# uses class names so you don't get an "incomplete" object
sub mysql_now {
  my $quick = $Bibliotech::Apache::QUICK{NOW};
  return $quick if defined $quick;
  my $now = Bibliotech::Date->new(Bibliotech::DBI->db_Main->selectrow_array('SELECT NOW()'));
  $Bibliotech::Apache::QUICK{NOW} = $now;
  return $now;
}

# seed a date that is literally zero.... use to represent invalid dates
sub zero {
  DateTime->from_epoch(epoch => 0);
}

# detect a date created with zero()
sub invalid {
  shift->epoch == 0;
}

sub valid {
  !shift->invalid;
}

sub table {
  'date';  # not true! no table exists, this is for compatibility
}

sub label {
  shift->strftime('%a %b %d %Y');
}

sub hm {
  shift->strftime('%H:%M %Z');
}

sub label_plus_time {
  my $self = shift;
  my $label = $self->label;
  my $hm = $self->hm;
  return wantarray ? ($label, $hm) : "$label $hm";
}

sub ymdhm {
  shift->strftime('%Y-%m-%d %H:%M');
}

sub citation {
  my $self = shift;
  return '' if $self->invalid;
  return $self->strftime('%d %b %Y');
}

sub search_value {
  shift->ymd(@_);
}

sub ymd_ordered_cut {
  shift->ymd(@_);
}

sub link {
  my $self = shift;
  $self->SUPER::link(@_) . ' at ' . $self->hm;
}

sub has_been_passed {
  my $self = shift;
  # can use DateTime->now interchangably in theory, but in practice the clock on the database server might be off
  # so it's best to use the now() from wherever you plan to derive data values... best comparing to database time
  my $now = $self->mysql_now;
  return $now < $self;
}

sub has_been_reached {
  my $self = shift;
  # can use DateTime->now interchangably in theory, but in practice the clock on the database server might be off
  # so it's best to use the now() from wherever you plan to derive data values... best comparing to database time
  my $now = $self->mysql_now;
  return $self < $now;
}

sub clone_if_necessary_for_tz {
  my ($self, $tz) = @_;
  return $self if $self->strftime('%Z') eq $tz;
  my $clone = DateTime::clone($self);
  $clone->set_time_zone('UTC');
  return $clone;
}

sub utc {
  shift->clone_if_necessary_for_tz('UTC');
}

sub iso8601 {
  # oddly DateTime::Format::ISO8601 only parses and does not format so call strftime()
  shift->strftime('%Y-%m-%dT%H:%M:%S%z');
}

sub iso8601_utc {
  shift->utc->strftime('%Y-%m-%dT%H:%M:%SZ');  # differs from above by '%z' -> 'Z'
}

sub json_content {
  shift->utc->strftime('%a, %d %b %Y %H:%M:%S GMT');
}

sub str_until_hms {
  my $self = shift;
  my $duration = $self - $self->mysql_now;
  return 'now' unless $duration->is_positive;
  $duration->in_units('hours', 'minutes', 'seconds');
  my $hours   = $duration->hours;
  my $minutes = $duration->minutes;
  my $seconds = $duration->seconds;
  return join(' ',
	      'in',
	      Bibliotech::Util::speech_join
	      ('and',
	       grep { $_ }
	       (($hours   ? Bibliotech::Util::plural($hours,   'hour')   : undef),
		($minutes ? Bibliotech::Util::plural($minutes, 'minute') : undef),
		($seconds ? Bibliotech::Util::plural($seconds, 'second') : undef),
		)
	       )
	      );
}

sub latest {
  my $self = shift;
  my $values_ref = shift;
  my @values = @{$values_ref || {}};
  unshift @values, $self if ref $self;
  my %options = @_;
  my $log = $options{log};
  $log->debug('latest() with choices: ['.join(', ', map { defined $_ ? "$_" : 'undef' } @values).']') if $log;
  my $operation = $options{operation} || 'latest';
  my $find_latest = $operation eq 'latest';
  my $only_current = $options{only_current} ? 1 : 0;
  my $winner;
  foreach my $timestamp (@values) {
    next if !defined $timestamp;
    die "not a Bibliotech::Date object: $timestamp" unless UNIVERSAL::isa($timestamp, 'Bibliotech::Date');
    if ($timestamp->incomplete) {
      $log->debug("$timestamp is incomplete") if $log;
      next;
    }
    if ($only_current and $timestamp->has_been_passed) {
      if ($log) {
	my $epoch = $timestamp->epoch;
	my $now = Bibliotech::Date->mysql_now;
	my $now_epoch = $now->epoch;
	$log->debug("$timestamp ($epoch) disregarded because not current, now: $now ($now_epoch)");
      }
      next;
    }
    if (!defined $winner) {
      $winner = $timestamp;
    }
    else {
      if ($find_latest) {
	$winner = $timestamp if $timestamp > $winner;
      }
      else {
	$winner = $timestamp if $timestamp < $winner;
      }
    }
  }
  die 'could not find latest timestamp in this list: '.join(', ', @values)
      if $options{die_if_none} and !defined($winner);
  $log->debug("latest() winner: $winner") if $log;
  return $winner;
}

sub earliest {
  latest(@_, operation => 'earliest');
}

sub DESTROY {
  # intentionally empty
  # override Class::DBI version otherwise it will try to query the object for changes
}

# Class::DBI method for strings
sub stringify_self {
  shift->mysql_datetime;
}

sub standard_annotation_text {
  my ($self, $bibliotech, $register) = @_;
  my $sitename = $bibliotech->sitename;
  my $date = $self->label;
  return "This is a list of the articles and links that have been posted by $sitename users on $date.
          To create your own collection, $register";
}

package Bibliotech::Date::Incomplete;
use base ('DateTime::Incomplete', 'Bibliotech::Date');

sub incomplete {
  1;
}

sub invalid {
  # this needs some explaining...
  # ok, first off, we are not going to do the epoch == 0 test for complete dates because we never have one
  # so, we are a valid incomplete date if any part of the date is defined
  # we are only invalid if ALL parts are zero
  shift->mysql_datetime eq '0000-00-00 00:00:00';
}

sub epoch {
  0;
}

sub mysql_format {
  my $str = shift->SUPER::mysql_format(@_);
  $str =~ s/x/0/g;
  return $str;
}

sub citation {
  my $str = shift->SUPER::citation;
  $str =~ s/ xxxx$/ (no year)/;
  $str =~ s/x+ ?//g;
  return $str;
}

sub json_content {
  my $str = shift->SUPER::json_content(@_);
  $str =~ s/x/0/g;
  return $str;
}

sub ymd_ordered_cut {
  my $self = shift;
  my $year  = $self->year  or return undef;
  my $month = $self->month or return $year;
  my $day   = $self->day   or return sprintf('%04d-%02d', $year, $month);
  return sprintf('%04d-%02d-%02d', $year, $month, $day);
}

1;
__END__
