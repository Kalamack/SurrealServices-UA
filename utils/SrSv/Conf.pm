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

package SrSv::Conf;

use strict;

use SrSv::SimpleHash qw(read_hash);

our %conffiles;

=cut
our $prefix;
BEGIN {
	if(main::PREFIX()) {
		$prefix = main::PREFIX();
	} else {
		$prefix = '.';
	}
}
=cut

sub install_conf($$) {
	no strict 'refs';
	my ($pkg, $file) = @_;

	*{"${pkg}::$file\_conf"} = $conffiles{$file};
}

sub import {
	my ($pkg, @files) = @_;

	foreach my $file (@files) {
		unless(defined $conffiles{$file}) {
			$conffiles{$file} = { read_hash(main::PREFIX()."/config/$file.conf") };
		}

		install_conf(caller(), $file);
	}
}

1;
