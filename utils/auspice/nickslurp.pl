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

$dbh = DBI->connect("DBI:mysql:services", "services", "yQ0AaCLdMhfEBTpxwc0OWw", {  AutoCommit => 1, RaiseError => 1 });

$register = $dbh->prepare("INSERT IGNORE INTO nickreg SET nick=?, pass=?, email=?, regd=?, last=?, flags=1, ident=?, vhost=?, gecos=?, quit=?");
$create_alias = $dbh->prepare("INSERT IGNORE INTO nickalias SET root=?, alias=?");

$time = time();

open FILE, $ARGV[0];

while(@in = split(/;/, <FILE>)) {
	next unless($in[2] eq 'slave:no');

	my ($ident, $host) = split('@', $in[3]) or ('', '');
	next unless $ident;

	@data = ($in[0], $in[1], $in[6], $in[4], $time, $ident, $host, $in[17], $in[16]);
	print join(', ', @data), "\n";
	$register->execute(@data);
	$create_alias->execute($in[0], $in[0]);
}

open FILE, $ARGV[0];

while(@in = split(/;/, <FILE>)) {
	next unless($in[2] eq 'slave:yes');

	@data = ($in[3], $in[0]);
	print join(', ', @data), "\n";
	$create_alias->execute(@data);
}
