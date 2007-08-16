package Bibliotech::ApacheInit;
use strict;
use Bibliotech::ApacheProper;

# just using Bibliotech::Config causes the configuration to preload:
use Bibliotech::Config;

# load this so the heavy config setup is done:
use Bibliotech::Apache;

# get the date code:
use Bibliotech::DBI;

sub handler {

  eval {
    # force a mysqld connection to be opened
    my ($now) = Bibliotech::Date->mysql_now;

    # force a memcached connection to be opened
    $Bibliotech::Apache::MEMCACHE->get('DB');

    # force the log to be opened
    $Bibliotech::Apache::LOG->info('child coming into service');
  };
  warn "Bibliotech::ApacheInit reports: $@\n" if $@;

  return OK;
}

1;
__END__
