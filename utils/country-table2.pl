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
	countrydb_url =>  'http://www.maxmind.com/download/geoip/database/GeoIPCountryCSV.zip',
	#countrydb_url => 'http://www.tabris.net/tmp/GeoIPCountryCSV.zip',
	srcname => 'GeoIPCountryCSV.zip',
	unpackname => 'GeoIPCountryWhois.csv',
};

main();
exit 0;

sub main() {
	downloadData();
	print "Connecting to database...\n";
	my $dbh = dbConnect();
	print "Creating new table...\n";
	newTable($dbh);
	print "Inserting data...     ";
	loadData($dbh);
	cleanup($dbh);
	$dbh->disconnect();
	print "Country table update complete.\n";
}

sub downloadData() {
	# This MAY be implementable with an open of a pipe
	# pipe the output of wget through gzip -d
	# and then into the load-loop.
	# It's a bit heavy to run directly from inside services however.
	# I'd recommend it be run as a crontab script separate from services.

	my (@stats, $date, $size);
	my $srcPath = PREFIX.'/data/'.srcname;
	if(@stats = stat($srcPath)) {
		print "Checking for updated country data...\n";
		my $header = qx "wget --spider -S ".countrydb_url." 2>&1";
		($date) = ($header =~ /Last-Modified: (.*)/);
		($size) = ($header =~ /Content-Length: (.*)/);
	}

	if(@stats and $stats[7] == $size and $stats[9] >= str2time($date)) {
		print "Country data is up to date.\n";
	} else {
		print "Downloading country data...\n";

		unlink $srcPath;
		system('wget '.countrydb_url." -O $srcPath");
		unless(-e $srcPath) {
			print STDERR "FATAL: Download failed.\n";
			exit;
		}
	}

	my $unpackPath = PREFIX.'/data/'.unpackname;
	print "Decompressing...\n";
	unlink $unpackPath;
	system("unzip $srcPath -d ".PREFIX.'/data/');
	unless(-f $unpackPath) {
		print STDERR "FATAL: Decompression failed.\n";
		exit;
	}
}

sub dbConnect() {
	my $dbh;
	eval { 
		$dbh = DBI->connect("DBI:mysql:".sql_conf_mysql_db, sql_conf_mysql_user, sql_conf_mysql_pass,
			{  AutoCommit => 1, RaiseError => 1 })
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
	$dbh->{RaiseError} = 1;
	$dbh->{PrintError} = 1;

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
	$| = 1;
	my $unpackPath = PREFIX.'/data/'.unpackname;
	my ($lines) = qx{wc -l $unpackPath};
	my $div = int($lines/100);
	my ($i, @entries);

	open ((my $COUNTRYTABLE), '<', $unpackPath);
	my $add_entry = $dbh->prepare("INSERT INTO newcountry SET low=INET_ATON(?), high=INET_ATON(?), country=?");
	$dbh->do("ALTER TABLE `newcountry` DISABLE KEYS");
	$dbh->do("LOCK TABLES newcountry WRITE");
	while(my $x = <$COUNTRYTABLE>) {
		if($i == 0 or !($i % $div)) {
			printf("\b\b\b\b%3d%", ($i/$lines)*100);
		}
	
		chomp $x;
		#"2.6.190.56","2.6.190.63","33996344","33996351","GB","United Kingdom"
		#$x =~ /\"(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\"\,\"(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\"\,\"(\d+)\"\,\"(\d+)\"\,\"\w{2}\",\"(.+)\"/;
		$x =~ s/\"//g;
		my ($low, $high, undef, undef, $country, undef) = split(',', $x);
		#$add_entry->execute($low, $high, $country);
		push @entries,
			'(INET_ATON('.$dbh->quote($low).'),'.'INET_ATON('.$dbh->quote($high).'),'.$dbh->quote($country).')';
		if(scalar(@entries) >= 100) { #1000 only gives another 10% boost for 10x as much memory
			$dbh->do("INSERT IGNORE INTO newcountry (low, high, country) VALUES ".join(',', @entries));
			@entries = ();
		}

		$i++;
	}
	$dbh->do("INSERT IGNORE INTO newcountry (low, high, country) VALUES ".join(',', @entries)) if scalar(@entries);
	$dbh->do("UNLOCK TABLES");
	$dbh->do("ALTER TABLE `newcountry` ENABLE KEYS");
	close $COUNTRYTABLE;
}

sub cleanup($) {
	my ($dbh) = @_;

	print "\b\b\b\bdone.\nRemoving old table...\n";
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
	unlink PREFIX.'/data/'.unpackname;
}
