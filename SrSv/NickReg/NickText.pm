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

package SrSv::NickReg::NickText;

use strict;

use Exporter 'import';

BEGIN {
	my %constants = (
		NTF_QUIT	=> 1,
		NTF_GREET	=> 2,
		NTF_JOIN	=> 3,
		NTF_AUTH	=> 4,
		NTF_UMODE	=> 5,
		NTF_VACATION	=> 6,
		NTF_AUTHCODE	=> 7,
		NTF_PROFILE	=> 8,
		NTF_VHOST_REQ	=> 9,
	);
	require constant; import constant \%constants;
	our @EXPORT = keys(%constants);
}

1;
