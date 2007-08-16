package Bibliotech::Unwritten;
use strict;
use base 'Class::Accessor';

use overload
    '""' => sub { shift->stringify_self; },
    bool => sub { UNIVERSAL::isa(shift, 'Bibliotech::Unwritten'); },
    fallback => 1;

sub update {
  delete shift->{__Changed};
}

sub stringify_self {
  return overload::StrVal(shift) if caller(1) =~ /^(Data|Devel)::/;  # react normally to Perl introspective modules
  return '[Unwritten]';
}

1;
__END__
