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

package SrSv::Debug;

use strict;

our @subs;
BEGIN {
	@subs = (
		sub () { 0 },
		sub () { 1 }
	);
}

our %debug_pkgs;
our $enabled;

sub enable {
	$enabled = 1;
}

sub import {
	no strict 'refs';
	no warnings 'uninitialized';
	my ($package) = caller;
	
	if($debug_pkgs{ALL}) {
		*{"$package\::DEBUG"} = $subs[1];
	} else {
		*{"$package\::DEBUG"} = $subs[$debug_pkgs{$package}];
	}

	*{"$package\::DEBUG_ANY"} = $subs[$enabled];
}

1;
