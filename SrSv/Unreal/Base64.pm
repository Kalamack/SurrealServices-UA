#       This file is part of SurrealServices.
#
#       SurrealServices is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#
#       SurrealServices is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with SurrealServices; if not, write to the Free Software
#       Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package SrSv::Unreal::Base64;

=head1 NAME

SrSv::Unreal::Base64 - Implementation of the UnrealIRCd Base64 encoding

=cut

use strict;
use SrSv::64bit;
BEGIN {
	if(!HAS_64BIT_INT) {
		eval {
			require Math::BigInt;
			import Math::BigInt try => 'GMP';
		};
		if($@) {
			print STDERR "Running old version of perl/Math::BigInt.\n", $@, "Trying again.\n";
			require Math::BigInt;
			import Math::BigInt;
		}
	}
}

use Exporter 'import';
BEGIN { our @EXPORT_OK = qw(b64toi itob64); }

# ':' and '#' and '&' and '+' and '@' must never be in this table. */
# these tables must NEVER CHANGE! >) */
our @int6_to_base64_map = (
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D',
            'E', 'F',
        'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
            'U', 'V',
        'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j',
            'k', 'l',
        'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
            '{', '}'
);

our @base64_to_int6_map = (
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, -1, -1, -1, -1, -1, -1,
        -1, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
        25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, -1, -1, -1, -1, -1,
        -1, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50,
        51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, -1, 63, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1
);

*b64toi = \&base64_to_int;
sub base64_to_int($) {
	my ($base64) = @_;
	my $val = 0;
	#wKgIAw==
	if(length($base64) > 8) {
		warn "greater-than-32bit base64($base64) in base64_to_int";
		$val = (HAS_64BIT_INT ? 0 : Math::BigInt->bzero());
	} else {
		$val = 0;
	}

	foreach my $ch (split(//, $base64)) {
		$val <<= 6;
		$val += $base64_to_int6_map[ord($ch)];
	}
	return $val;
}

*itob64 = \&int_to_base64;
sub int_to_base64($) {
	my ($val) = @_;

	my $base64 = '';
	do {
		$base64 .= $int6_to_base64_map[$val & 63];
	} while ($val >>= 6);
	return scalar reverse($base64);
}

1;

__END__

=head1 SYNOPSIS

 use SrSv::Unreal::Base64;
 $integer = b64toi($base64);
 $base64 = itob64($integer);

=head1 NOTES

As far as I know, all usage of these functions will accept or return
a 32-bit integer. The only exception is for IPv6, but NICKIP uses the
standard table anyway.
