# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::SpamDNSBL class does NOT retrieve
# citation data; it attempts to catch spam by checking URL's against
# DNS blacklists.

package Bibliotech::CitationSource::SpamDNSBL;
use strict;
use base 'Bibliotech::CitationSource';
use Net::hostent;
use Socket;

our $DNS_LISTS  = __PACKAGE__->cfg('DNS_LISTS')  || ['sbl.spamhaus.org', 'multi.surbl.org'];
our $WHITE_LIST = __PACKAGE__->cfg('WHITE_LIST') || [];
our $SCORE      = __PACKAGE__->cfg('SCORE')      || 2;

sub api_version {
  1;
}

sub name {
  'SpamDNSBL';
}

sub version {
  '1.1.2.1';
}

sub reverse_ip_address {
  join('.', reverse(split(/\./, pop)));
}

sub is_127_ip_address {
  pop =~ /^127\./;
}

sub is_whitelisted {
  my $entity     = shift or return;
  my $white_list = shift or return;
  return grep { $entity eq $_ } @{$white_list} ? 1 : 0;
}

sub is_reverse_ip_address_on_list {
  my $reverse_ip_address = shift or return;
  my $dns_list           = shift or return;
  my $query              = $reverse_ip_address.'.'.$dns_list;
  my $host       	 = gethost($query) or return;
  my $answer             = inet_ntoa($host->addr) or return;
  return if !is_127_ip_address($answer);  # that would be strange but if it happens it is not a spam confirmation
  return 1;  # confirm spam
}

sub is_ip_address_on_list {
  my $ip_address = shift or return;
  my $dns_list   = shift or return;
  my $white_list = shift || [];
  return if is_whitelisted($ip_address, $white_list);
  return is_reverse_ip_address_on_list(reverse_ip_address($ip_address), $dns_list);
}

sub is_ip_address_on_lists {
  my $ip_address         = shift or return;
  my $list_of_dns_lists  = shift or return;
  my $white_list         = shift || [];
  return if is_whitelisted($ip_address, $white_list);
  my $reverse_ip_address = reverse_ip_address($ip_address);
  foreach my $dns_list (@{$list_of_dns_lists}) {
    return $dns_list if is_reverse_ip_address_on_list($reverse_ip_address, $dns_list);
  }
  return;
}

sub is_host_on_lists {
  my $hostname          = shift or return;
  my $list_of_dns_lists = shift or return;
  my $white_list        = shift || [];
  my $host              = gethost($hostname) or return;
  foreach my $address (@{$host->addr_list}) {
    my $dns_list = is_ip_address_on_lists(inet_ntoa($address), $list_of_dns_lists, $white_list);
    return $dns_list if defined $dns_list;
  }
  return;
}

sub is_spam_uri {
  my $uri      = shift         or return;
  UNIVERSAL::can($uri, 'host') or return;
  my $hostname = $uri->host    or return;
  return is_host_on_lists($hostname, $DNS_LISTS, $WHITE_LIST);
}

sub potential_understands {
  $SCORE;
}

# score is an option but 2 is recommended to signal affirmative but
# not the best score which protects domains recognized by other
# modules
sub understands {
  my ($self, $uri) = @_;
  return is_spam_uri($uri) ? $SCORE : 0;
}

sub filter {
  my ($self, $uri) = @_;
  my $dns_list = is_spam_uri($uri);
  return unless defined $dns_list;
  $self->errstr('Sorry, you cannot add this URI because it appears in a spam blacklist: '.$dns_list);
  return '';  # signal an abort!
}

# there is no citations() method because this module is not designed to get citations
# we are just taking advantage of the filter() method to abort spam URI's

1;
__END__
