#!/usr/bin/perl


#       This file is part of SurrealServices.
#
#       SurrealServices is free software; you can redistribute it and/or modify
#       it under the terms of the GNU Lesser General Public License version 2,
#       as published by the Free Software Foundation.
#
#       SurrealServices is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with SurrealServices; if not, write to the Free Software
#       Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


=cut

THIS CODE IS alpha only, and untested. Don't just trust it blindly.

=cut

use strict;
use warnings;

sub isAlpha($) {
	my ($char) = @_;
	return ($char =~ /[A-Z]/);
}

sub getBase36($) {
	my ($char) = @_;
	if(isAlpha($char)) {
		my $val = (ord($char) - ord('A')) + 10;
		#print "$val\n";
		return $val;
	} else {
		return int($char);
	}
}

sub decodeUUID($) {
	my ($UUID) = @_;
	my @chars = split(//, $UUID);
	my @sidC = @chars[0..2];
	my @uidC = @chars[3..8];
	my $sidN = int($sidC[0]) << (4 + (6 * 2));
	$sidN |= getBase36($sidC[1]) << (4 + (6 * 1));
	$sidN |= getBase36($sidC[2]) << (4 + (6 * 0));
	my $uidN = 0;
	foreach my $char (@uidC) {
		#print "$char\n";
		$uidN <<= 6;
		$uidN |= getBase36($char);
	}
	return (($sidN << 48) | $uidN);
}

my $int = decodeUUID('751AAAAAA');
print "$int\n";
print log($int)/log(2), "\n";
