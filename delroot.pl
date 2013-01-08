#!/usr/bin/perl

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

use DBI;

BEGIN {
	use Cwd qw( abs_path getcwd );
	use File::Basename;
	my %constants = (
		CWD => getcwd(),
		PREFIX => dirname(abs_path($0)),
	);
	require constant; import constant(\%constants);
}
chdir PREFIX;
use lib PREFIX;
		
use SrSv::Conf 'sql';

$dbh = DBI->connect('DBI:mysql:'.$sql_conf{'mysql-db'}, $sql_conf{'mysql-user'}, $sql_conf{'mysql-pass'}, 
	{  AutoCommit => 1, RaiseError => 1 });

$get_root_nick = $dbh->prepare("SELECT nickreg.nick FROM nickalias,nickreg WHERE nickalias.nrid=nickreg.id AND alias=?");
$del_svsop = $dbh->prepare("DELETE FROM svsop USING svsop, nickreg WHERE svsop.nrid=nickreg.id AND nickreg.nick=?");

$get_root_nick->execute($ARGV[0]);
my ($root) = $get_root_nick->fetchrow_array;
$get_root_nick->finish;

unless($root) {
	print "That nick does not exist.\n";
	exit;
}

$del_svsop->execute($root);
$del_svsop->finish;

print "$root has been stripped of all rank.\n";
