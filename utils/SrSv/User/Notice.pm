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

package SrSv::User::Notice;

use strict;

use Exporter 'import';
BEGIN { our @EXPORT = qw(notice user_die) }

use SrSv::User qw(get_user_nick);

sub notice($@) {
	my $user = shift;
	
	# FIXME: ref to 'NickServ' should call for the agent-nick in nickserv.pm,
	# but that's not available at this layer, so we'd be making
	# a blind reference to something that _might_ be undef
	ircd::notice($user->{AGENT} || 'NickServ', get_user_nick($user), @_);
}

sub user_die($@) {
	&notice;

	die 'user';
}

1;
