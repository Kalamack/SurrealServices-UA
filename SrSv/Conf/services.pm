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

package SrSv::Conf::services;

use SrSv::Conf::Parameters services => [
	[noexpire => undef],
	[nickexpire => 21],
	[vacationexpire => 90],
	[nearexpire => 7],
	[chanexpire => 21],
	[validate_email => undef],
	[validate_expire => 1],
	[clone_limit => 3],
	[chankilltime => 86400],

	[default_protect => 'normal'],
	[default_chanbot => undef],
	[default_channel_mlock => '+nrt'],
	[old_user_age => 300],
	[chanreg_needs_oper => 0],

	[log_overrides => 0],

	[botserv => undef],
	[nickserv => undef],
	[chanserv => undef],
	[memoserv => undef],
	[adminserv => undef],
	[operserv => undef],
	[hostserv => undef],

];

1;
