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

#  SurrealChat.net does not provide the Country/Allocation data,
#  is in no way associated with maxmind.com,
#  nor are we providing a license to download/use it.
#  Be sure to direct availability/accuracy/licensing questions to maxmind.com

use strict;
use DBI;

BEGIN {
	use Cwd qw( abs_path getcwd );
	use File::Basename;
	my %constants = (
		CWD => getcwd(),
		PREFIX => abs_path(dirname(abs_path($0)).'/..'),
	);
	require constant; import constant(\%constants);
}
chdir PREFIX;
use lib PREFIX;

use Date::Parse;

use SrSv::Conf::sql;
use SrSv::Conf2Consts qw( sql );

use constant {
	countrydb_url => 'rsync://countries-ns.mdc.dk/zone/zz.countries.nerd.dk.rbldnsd',
	srcname => 'zz.countries.nerd.dk.rbldnsd',
};

main();
exit 0;

sub main() {

	print "Synching country-data file...\n";
	downloadData();
	print "Connecting to database...\n";
	my $dbh = dbConnect();
	print "Creating new table...\n";
	newTable($dbh);
	print "Inserting data...     ";
	loadData($dbh);
	print "Removing old table...\n";
	cleanup($dbh);
	$dbh->disconnect();
	print "Country table update complete.\n";
}

sub downloadData() {
	my $srcPath = PREFIX.'/data/'.srcname;
	system('rsync -azvv --progress '.countrydb_url.' '.$srcPath);
	unless(-e $srcPath) {
		print STDERR "FATAL: Download failed.\n";
		exit -1;
	}
}

sub dbConnect() {

	my $dbh;
        eval { 
		$dbh = DBI->connect("DBI:mysql:"..sql_conf_mysql_db, sql_conf_mysql_user, sql_conf_mysql_pass,
			{  AutoCommit => 1, RaiseError => 1, PrintError => 1 })
	};

	if($@) {
		print STDERR "FATAL: Can't connect to database:\n$@\n";
		print STDERR "You must edit config/sql.conf and create a corresponding\nMySQL user and database!\n\n";
		exit -1;
	}
	return $dbh;
}


sub newTable($) {
	my ($dbh) = @_;

	$dbh->do("DROP TABLE IF EXISTS newcountry");
	$dbh->do(
	"CREATE TABLE `newcountry` (
	  `low` int unsigned NOT NULL default 0,
	  `high` int unsigned NOT NULL default 0,
	  `country` char(2) NOT NULL default '-',
	  PRIMARY KEY (`low`, `high`)
	) TYPE=MyISAM"
	);
}

sub loadData($) {
	my ($dbh) = @_;
	my $add_entry = $dbh->prepare("INSERT IGNORE INTO newcountry SET low=?, high=?, country=?");

	$| = 1;
	my $unpackPath = PREFIX.'/data/'.srcname;
	my ($lines) = qx{wc -l $unpackPath};
	my $div = int($lines/100);
	my ($i, @entries);

	open ((my $COUNTRYTABLE), '<', $unpackPath);
	$dbh->do("ALTER TABLE `newcountry` DISABLE KEYS");
	$dbh->do("LOCK TABLES newcountry WRITE");
	while(my $x = <$COUNTRYTABLE>) {
		if($i == 0 or !($i % $div)) {
			printf("\b\b\b\b%3d%", ($i/$lines)*100);
		}

		chomp $x;
		#85.10.224.152/29 :127.0.0.20:ad
		if ($x =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\/(\d{1,2}) \:(\S+)\:([a-z]{1,2})$/) {
			my $low = $1 << 24 | $2 << 16 | $3 << 8 | $4;
			my $high = $low + ((2 << (31 - $5)));
			my $country = $7;
			next if lc $country eq 'eu';
			push @entries, '('.$dbh->quote($low).','.$dbh->quote($high).','.$dbh->quote($country).')';
			if(scalar(@entries) >= 100) { #1000 only gives another 10% boost for 10x as much memory
			    $dbh->do("INSERT IGNORE INTO newcountry (low, high, country) VALUES ".join(',', @entries));
			    @entries = ();
			}
		}

		$i++;
	}
	$dbh->do("INSERT IGNORE INTO newcountry (low, high, country) VALUES ".join(',', @entries)) if scalar(@entries);

	$dbh->do("UNLOCK TABLES");
	$dbh->do("ALTER TABLE `newcountry` ENABLE KEYS");
	close $COUNTRYTABLE;
	print "\b\b\b\bdone.\n";
}

sub cleanup($) {
	my ($dbh) = @_;

	$dbh->do("DROP TABLE IF EXISTS `oldcountry`");
	print "Renaming new table...\n";
	$dbh->{RaiseError} = 0;
	$dbh->do("OPTIMIZE TABLE `newcountry`");
	$dbh->do("ANALYZE TABLE `newcountry`");
	# Doing the renames cannot be done atomically
	# as sometimes `country` doesn't exist yet.
	$dbh->do("RENAME TABLE `country` TO `oldcountry`");
	$dbh->do("RENAME TABLE `newcountry` TO `country`");
	$dbh->do("DROP TABLE `oldcountry`");
}
