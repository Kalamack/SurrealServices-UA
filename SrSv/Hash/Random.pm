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

package SrSv::Hash::Random;

=head1 NAME

SrSv::Hash::Random - generates random strings for use as salt

=cut

use strict;
#use SrSv::Conf qw( main );

use Exporter 'import';
BEGIN {
        our @EXPORT = qw( randomByte randomBytes );
}

sub randomByte() {
	return chr(int(rand(256)));
}

sub randomBytes($) {
	my ($count) = @_;
	my $string;
	for(1..$count) {
		$string .= randomByte();
	}
	return $string;
}

=cut
sub randomBytes($) {
	my ($count) = @_;
	open((my $fh), '<', '/dev/urandom');
	binmode $fh;
	my $bytes = '';
	sysread($fh, $bytes, $count);
	close $fh;
	return $bytes;
}

sub randomByte() {
	return randomBytes(1);
}
=cut

1;

