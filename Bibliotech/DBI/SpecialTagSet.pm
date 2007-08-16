package Bibliotech::SpecialTagSet;
use strict;
use base 'Class::Accessor';

__PACKAGE__->mk_accessors(qw/name used rest/);

sub scan {
  my ($class, $tags_ref) = @_;
  my $obj = Bibliotech::SpecialTagSet::Geo->scan($tags_ref);
  return $obj if $obj;
  return undef;
}

package Bibliotech::SpecialTagSet::Geo;
use base 'Bibliotech::SpecialTagSet';

__PACKAGE__->mk_accessors(qw/latitude longitude/);

# $tags_ref is an arrayref that may contain strings (tag names) or objects (Bibliotech::Tag's) and this must work either way
sub scan {
  my ($class, $tags_ref) = @_;
  my @tags = @{$tags_ref};
  my @tagnames = map(UNIVERSAL::isa($_, 'Bibliotech::Tag') ? $_->name : $_, @tags);
  my %tags = map { UNIVERSAL::isa($_, 'Bibliotech::Tag') ? $_->name : $_ => $_; } @tags;
  if (my @geo = grep(/^geo:/, @tagnames) or defined $tags{geotagged}) {
    my @lat  = grep(/^geo:lat=[\-\+]?\d+(?:\.\d*)?$/,  @geo);
    my @long = grep(/^geo:long=[\-\+]?\d+(?:\.\d*)?$/, @geo);
    die "For geotagging, please provide the latitude as geo:lat=latitude and longitude as geo:long=longitude\n" if !@lat && !@long;
    die "For geotagging, please provide the latitude as geo:lat=latitude\n" unless @lat;
    die "For geotagging, please provide the longitude as geo:long=longitude\n" unless @long;
    die "For geotagging, please only provide one latitude tag and one longitude tag.\n" if @lat != 1 || @long != 1;
    die "Please use the tag \"geotagged\" when providing geo:lat=latitude and geo:long=longitude tags.\n" unless defined $tags{geotagged};
    my $lat = $lat[0];
    my $long = $long[0];
    my ($latvalue) = $lat =~ /^geo:lat=([\-\+]?\d+(?:\.\d*)?)$/;
    die "Cannot find latitude value.\n" unless defined $latvalue;
    die "Latitude value must be between -180 and +180.\n" unless -180 <= $latvalue && $latvalue <= 180;
    my ($longvalue) = $long =~ /^geo:long=([\-\+]?\d+(?:\.\d*)?)$/;
    die "Cannot find longitude value.\n" unless defined $longvalue;
    die "Longitude value must be between -180 and +180.\n" unless -180 <= $longvalue && $longvalue <= 180;
    my @used = ('geotagged', $tags{$lat}, $tags{$long});
    delete $tags{geotagged};
    delete $tags{$lat};
    delete $tags{$long};
    my @rest = values %tags;
    return $class->SUPER::new({name => 'Geo', used => \@used, rest => \@rest, latitude => $latvalue, longitude => $longvalue});
  }
  return undef;
}

1;
__END__
