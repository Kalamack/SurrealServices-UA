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

package SrSv::NickReg::User;

=head1 NAME

SrSv::NickReg::User - Determine which users are identified to which nicks

=cut

use strict;

use Exporter 'import';
BEGIN {
	our @EXPORT_OK = qw(
		is_identified chk_identified
		get_id_nicks
		get_nick_user_nicks get_nick_users get_nick_users_all
	);
}

use SrSv::Process::Init;
use SrSv::MySQL '$dbh';
use SrSv::User qw(:flags get_user_nick get_user_id);
use SrSv::User::Notice;
use SrSv::NickReg::Flags;
use SrSv::Errors;

my $find_user_tables = 'user JOIN nickid ON (user.id=nickid.id) JOIN nickalias ON (nickid.nrid=nickalias.nrid)';
require SrSv::MySQL::Stub;
import SrSv::MySQL::Stub {
	__get_nick_users => ['ARRAY', "SELECT user.nick, user.id
		FROM $find_user_tables WHERE nickalias.alias=? AND user.online=1"],
	__get_nick_users_all => ['ARRAY', "SELECT user.nick, user.id, user.online
		FROM $find_user_tables WHERE nickalias.alias=?"],
	__is_identified => ['SCALAR', "SELECT 1
		FROM $find_user_tables WHERE user.nick=? AND nickalias.alias=?"],
	__get_id_nicks => ['COLUMN', "SELECT nickreg.nick
		FROM nickid JOIN nickreg ON (nickid.nrid=nickreg.id) WHERE nickid.id=?"],
};

sub is_identified($$) {
	my ($user, $rnick) = @_;
	my $nick = get_user_nick($user);

	return __is_identified($nick, $rnick) ? 1 : 0;
}

sub chk_identified($;$) {
	my ($user, $nick) = @_;

	$nick = get_user_nick($user) unless $nick;

	nickserv::chk_registered($user, $nick) or return 0;

	unless(is_identified($user, $nick)) {
		notice($user, $err_deny);
		return 0;
	}

	return 1;
}

sub get_id_nicks($) {
	my ($user) = @_;
	my $id = get_user_id($user);

	return __get_id_nicks($id);
}

sub get_nick_user_nicks($) {
	my ($nick) = @_;

	return map $_->[0], __get_nick_users($nick);
}

sub get_nick_users($) {
	my ($nick) = @_;

	return map +{ NICK => $_->[0], ID => $_->[1], ONLINE => 1 }, __get_nick_users($nick);
}

sub get_nick_users_all($) {
	my ($nick) = @_;

	return map +{ NICK => $_->[0], ID => $_->[1], ONLINE => $_->[2] }, __get_nick_users_all($nick);
}

1;
