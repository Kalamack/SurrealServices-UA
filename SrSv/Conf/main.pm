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

package SrSv::Conf::main;

use SrSv::Conf::Parameters main => [
	qw(local remote port numeric pass load email replyto),
	[info => 'SurrealServices'],
	[procs => 4],
	[diag => '#Diagnostics'],
	[netname => 'Network'],
	[sig => 'Thank you for chatting with us.'],
	[unsyncserver => undef],
	[nomail => undef],
	[logmail => undef],
	[hashed_passwords => undef],
	[ban_webchat_prefixes => 'java|htIRC'],
	[ipv6 => 0], # not enabled by default as not all systems support it
	[tokens => 1], # turn off for debugging, so debug-output is easier to read
	[highqueue => 20],
	[operchan => undef],
];

1;
