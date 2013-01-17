#       This file is part of SurrealServices.
#
#       SurrealServices is free software; you can redistribute it and/or modify
#       it under the terms of the GNU Lesser General Public License version 2.1,
#       as published by the Free Software Foundation.
#
#       SurrealServices is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU Lesser General Public License
#       along with SurrealServices; if not, write to the Free Software
#       Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


=cut

THIS CODE IS alpha only, and untested. Don't just trust it blindly.

=cut

package SrSv::Insp::UUID;

use strict;
use warnings;


use Exporter qw( import );
BEGIN {
	our @EXPORT = qw( decodeUUID encodeUUID );
}

use constant {
	ORD_A => ord('A'),
	SID_BITS => 24,
	UID_BITS => 40,
	CHAR_BITS => 6,
	CHAR_MASK => 63,
	# the 24 here is SID_BITS, the 40 is UID_BITS
	# but you can't reference a constant in a constant.
	SID_BITMASK => (((2**24)-1) << 40),
	UID_BITMASK => ~(((2**24)-1) << 40),
};

sub isAlpha($) {
	my ($char) = @_;
	return ($char =~ /^[A-Z]$/);
}
sub getBase36($) {
	my ($char) = @_;
	if(isAlpha($char)) {
		return (ord($char) - ORD_A);
	} else {
		return int($char) + 26;
	}
}
sub decodeSID(@) {
	my ($a, $b, $c) = @_;
	if(length($a) > 1) {
		($a, $b, $c) = split(//, $a);
	}
	my $sidN = 0;
	foreach my $char ($a,$b,$c) {
		$sidN <<= 6;
		$sidN |= getBase36($char);
	}
	return $sidN;
}
sub decodeUUID($) {
	my ($UUID) = @_;
	my @chars = split(//, $UUID);
	#my @sidC = @chars[0..2];
	#my @uidC = @chars[3..8];
	my $sidN = decodeSID(@chars[0..2]);
	my $uidN = 0;
	foreach my $char (@chars[3..8]) {
		$uidN <<= 6;
		$uidN |= getBase36($char);
	}
	return (($sidN << UID_BITS) | $uidN);
}

sub encodeChar($) {
	my ($ch) = @_;
	if($ch < 26) {
		$ch = chr(($ch) + ORD_A);
	} else {
		$ch -= 26;
	}
}
sub int2chars($$) {
	my ($id_int, $list) = @_;
	foreach my $ch (reverse @$list) {
		$ch = $id_int & CHAR_MASK;
		$id_int >>= CHAR_BITS;
		$ch = encodeChar($ch);
	}
}
sub encodeUUID($) {
	my ($int) = @_;
	my $SID_int = ($int & (SID_BITMASK)) >> UID_BITS;
	my $UID_int = $int & UID_BITMASK;
	my @SID = (0,0,0);
	int2chars($SID_int, \@SID);
	my @UID = (0,0,0,0,0,0);
	int2chars($UID_int, \@UID);
	print join('', @SID,@UID),"\n";
}

1;

=cut
my $int = decodeUUID('751AAAAAA');
print "$int\n";
print log($int)/log(2), "\n";
encodeUUID($int);
=cut
