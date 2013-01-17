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

%acc = (
	3 => 2,
	4 => 3,
	5 => 4,
	10 => 5,
	13 => 6
);

$dbh = DBI->connect("DBI:mysql:services", "services", "yQ0AaCLdMhfEBTpxwc0OWw", {  AutoCommit => 1, RaiseError => 1 });

$register = $dbh->prepare("INSERT IGNORE INTO chanreg SET chan=?, descrip=?, founder=?, pass=?, regd=?, last=?, topic=?, topicer='unknown', topicd=?, successor=?, bot=?");
$create_acc = $dbh->prepare("INSERT IGNORE INTO chanacc SET chan=?, nick=?, level=?, adder=?");

$time = time();

open FILE, $ARGV[0];

# 0name;1founder;2pass;3time_registered;4url;email;5mlock_key;6welcome;7hold;8mark;9freeze;10forbid;11successor;12mlock_link;13mlock_flood;14bot;15markreason;16freezereason;17holdreason;18lastgetpass;19access-level:nick:adder;20last_topic\ndesc

while(@in = split(/;/, <FILE>)) {
	die("Too many fields in $in[0]") if @in > 21;
	$topic = <FILE>; chomp $topic;
	$desc = <FILE>; chomp $desc;
	@data = ($in[0], $desc, $in[1], $in[2], $in[3], $time, $topic, $time, $in[12], $in[15]);
	print join(', ', @data), "\n";
	$register->execute(@data);
	$create_acc->execute($in[0], $in[1], 7, '');

	foreach $acc (split(/,/, $in[20])) {
		@d = split(/:/, $acc);
		next unless @d == 3;
		$d[0] = $acc{$d[0]};

		print "acc: ", join(', ', @d), "\n";
		$create_acc->execute($in[0], $d[1], $d[0], $d[2]);
	}
}

