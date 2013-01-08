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

#  SurrealChat.net does not provide the Blacklist Data
#  is in no way associated with dronebl.org,
#  nor are we providing a license to download/use it.
#  Be sure to direct availability/accuracy/licensing questions to 
#  http://dronebl.org/docs/howtouse

use strict;
use DBI;
use Cwd 'abs_path';
use File::Basename;

use Cwd qw( abs_path getcwd );
use File::Basename qw( dirname );
BEGIN {
	my %constants = (
		CWD => getcwd(),
		PREFIX => abs_path(dirname(abs_path($0)).'/../'),
	);
	require constant; import constant \%constants;
}
use lib PREFIX;

#Date::Parse might not be on the user's system, so we ship our own copy.
use Date::Parse;

use SrSv::SimpleHash qw(readHash);
use SrSv::Conf::sql;
use SrSv::Conf2Consts 'sql';

my $srcname = 'http://dronebl.org/buildzone.do';
my $bindip = undef;
my $unpackname = $srcname;
my $diffname = $srcname.'.diff';
my $agent = findAgent();

sub findAgent {
	my $agent;
	my $ret = system('which curl');
	if(($ret >> 8) == 0) {
		# we prefer curl b/c it can handle gzip compression!
		# we do IPv4 b/c either their IPv6 gateway or ours is SLOW
		# UPDATE 2011/05: due to DDoS, IPv4 is swamped, IPv6 is only way!
		$agent = 'curl --compressed --silent';
	} else {
		$agent = 'wget -q -O -';
	}
	return $agent;
}

my $OPMDATA;
unless(open $OPMDATA, '-|', "$agent $srcname") {
	print STDERR "FATAL: Processing failed.\n";
	exit -1;
}

print "Connecting to database...\n";

my $dbh;
eval { 
	$dbh = DBI->connect("DBI:mysql:".sql_conf_mysql_db, sql_conf_mysql_user, sql_conf_mysql_pass,
		{  AutoCommit => 1, RaiseError => 1, PrintError => 1 })
};

if($@) {
	print STDERR "FATAL: Can't connect to database:\n$@\n";
	print STDERR "You must have SrSv properly setup before you attempt to use this helper script.\n\n";
	exit -1;
}

print "Creating new table...\n";

$dbh->do("DROP TABLE IF EXISTS `newopm`");
$dbh->do(
"CREATE TEMPORARY TABLE `newopm` (
	`ipnum` int(11) unsigned NOT NULL default 0,
	`ipaddr` char(15) NOT NULL default '0.0.0.0',
	`type` tinyint(3) NOT NULL default 0,
	PRIMARY KEY (`ipnum`),
	UNIQUE KEY `addrkey` (`ipaddr`)
) Engine=Memory;"
);

sub save2DB($@) {
	my ($baseQuery, @rows) = @_;
	$dbh->do("$baseQuery ".join(',', @rows));
}

sub processData() {
	print "Inserting data...     ";

	$dbh->do("ALTER TABLE `newopm` DISABLE KEYS");
	$dbh->do("LOCK TABLES `newopm` WRITE");
	my $type;
	my $baseQuery = "REPLACE INTO `newopm` (ipnum, ipaddr, type) VALUES ";
	my @rows;
	my $count = 0;
	while(my $x = <$OPMDATA>) {
		chomp $x;
		if($x =~ /^:(\d{1,3}):/) {
			$type = $1;
		} elsif($x =~ /^(\d+\.\d+\.\d+\.\d+)$/) {
			next unless $type;
			my $ipaddr = $1;
			push @rows, '(INET_ATON('.$dbh->quote($ipaddr).'),'.$dbh->quote($ipaddr).','.$type.')';
			$count++;
			if(scalar(@rows) > 1000) {
				save2DB($baseQuery, @rows);
				@rows = ();
			}
		}
	}
	die "No entries found\n" unless $count;

	#rename($unpackname, $srcname.'.old');
	save2DB($baseQuery, @rows) if scalar(@rows);

	$dbh->do("UNLOCK TABLES");
	$dbh->do("ALTER TABLE `newopm` ENABLE KEYS");
}

processData();
close $OPMDATA;

print "done.\nRemoving old table...\n";
$dbh->do("DROP TABLE IF EXISTS `oldopm`");
$dbh->do("ALTER TABLE opm ENGINE=InnoDB");
$dbh->do("START TRANSACTION");
print "Renaming new table...\n";
#$dbh->{RaiseError} = $dbh->{PrintError} = 0; # the following commands can fail, but are harmless.
$dbh->do("TRUNCATE TABLE `opm`");
$dbh->do("INSERT INTO opm SELECT * FROM newopm");
$dbh->do("COMMIT");

print "Blacklist table update complete.\n";

exit;
