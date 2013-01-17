#	This file is part of SurrealServices.
#
#	SurrealServices is free software; you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation; either version 2 of the License, or
#	(at your option) any later version.
#
#	SurrealServices is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with SurrealServices; if not, write to the Free Software
#	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
package misc;
use strict;

sub isint($) {
	my($x) = shift;
	return (int($x) eq $x);
}

sub parse_quoted($) {
	my ($in) = @_;
	my @out;

	my @qs = (
		[qr/^\s*\"(.*?)(?<!\\)\"(.*)/,
		  sub { $_[0] =~ s/\\"/\"/g; return $_[0] }],
		[qr/^\s*\/(.*?)(?<!\\)\/(.*)/,
		  sub { $_[0] =~ s#\\/#/#g; return $_[0] }],
		[qr/(\S+)\s*(.*|$)/, undef]
	);

	do {
		foreach my $q (@qs) {
			my $str;
			my ($re, $trans) = @$q;
			
			if(my @x = ($in =~ $re)) {
				($str, $in) = @x;
				$str = &$trans($str) if $trans;
				push @out, $str;
				#print "str: $str\nin: $in\n";
			}
		}
	} while($in =~ /\S/);
	
	return @out;
}

use constant { ORD_A => ord('A') };

sub gen_uuid($$) {
	my ($groups, $length) = @_;
	my $emailreg_code = '';
	for(my $i = 1; $i <= $groups; $i++) {
		for (my $j = 1; $j <= $length; $j++) {
			my $ch;
			$emailreg_code .= (($ch = int(rand(36))) > 9 ? chr((ORD_A - 10) + $ch) : $ch);
		}
		$emailreg_code .= '-' unless $i >= $groups;
	}
	return $emailreg_code;
}

1;
