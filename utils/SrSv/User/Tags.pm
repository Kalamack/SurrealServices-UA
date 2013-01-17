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
BEGIN { our @EXPORT = qw(add_user_tag get_user_tags check_user_tags) }

use SrSv::User qw(get_user_nick get_user_id);

use SrSv::MySQL::Stub (
	__add_user_tag => ['INSERT', "INSERT IGNORE INTO usertags (userid, tag) VALUES (?,?)"],
	__get_user_tags => ['COLUMN', 'SELECT tag FROM usertags WHERE userid=?'],
	__check_user_tags => ['SCALAR', 'SELECT 1 FROM usertags WHERE userid=? AND tag=?'],
);

sub add_user_tag($$) {
	my ($user, $tag) = @_;
	return __add_user_tag(get_user_id($user), $tag);
}
sub get_user_tags($$) {
	my ($user, $tag) = @_;
	return __get_user_tags(get_user_id($user));
}
sub check_user_tags($$) {
	my ($user, $tag) = @_;
	return __check_user_tag(get_user_id($user), $tag);
}

1;
