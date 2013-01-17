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

package SrSv::OnIRC;

use strict;

BEGIN {
	our @ISA = qw(Exporter);
	our @EXPORT = qw(IRC_SERVER);
}

sub import {
	my ($pkg, $is_server) = @_;

	if($is_server) {
		*IRC_SERVER = sub () { 1 };
	}
	elsif(not defined *IRC_SERVER{CODE}) {
		*IRC_SERVER = sub () { 0 };
	}

	SrSv::OnIRC->export_to_level(1);
}

1;
