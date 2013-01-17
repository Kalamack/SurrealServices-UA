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

package SrSv::DB::Schema;

use strict;

use SrSv::MySQL qw( $dbh connectDB disconnectDB );
use SrSv::Conf2Consts qw( sql );

BEGIN {
	*PREFIX = \&main::PREFIX;
}


use Exporter 'import';
BEGIN {
	our @EXPORT = qw(
		upgrade_schema check_schema find_newest_schema
		do_sql_file );
};

sub find_newest_schema() {
	opendir((my $dh), "@{[PREFIX]}/sql/");
	my @schemas;
	while (my $dentry = readdir($dh)) {
		next if ($dentry =~ /^\.\.?$/);
		if($dentry =~ /^(\d+)\.sql$/) {
			push @schemas, $1;
		}
	}
	@schemas = reverse sort { $a <=> $b } @schemas;
	return $schemas[0];
}
sub upgrade_schema($) {
	my ($ver) = @_;
	opendir((my $dh), "@{[PREFIX]}/sql/");
	my @schemas;
	while (my $dentry = readdir($dh)) {
		next if ($dentry =~ /^\.\.?$/);
		if($dentry =~ /^(\d+)\.sql$/) {
			push @schemas, $1;
		}
	}
	@schemas = sort { $a <=> $b } @schemas;
	while(scalar(@schemas) && $schemas[0] <= $ver) {
		shift @schemas;
	}
	foreach my $schema (@schemas) {
		#print "@{[PREFIX]}/sql/${schema}.sql\n";
		do_sql_file("@{[PREFIX]}/sql/${schema}.sql");
	}
}
sub check_schema() {
	my $disconnect = 0;
	if(!defined($dbh)) {
		connectDB();
		$disconnect = 1;
	}
	# SHOW TABLES WHERE doesn't work for MySQL 4.x.
	my $tables = $dbh->selectall_arrayref("SHOW TABLES");
	my ($found, undef) = grep { m"srsv_schema" } map { $_->[0] } @$tables;
	if(defined $found) {
	} else {
		return 0;
	}
	my $findSchemaVer = $dbh->prepare("SELECT `ver` FROM `srsv_schema`");
	$findSchemaVer->execute();
	my ($ver) = $findSchemaVer->fetchrow_array();
	$findSchemaVer->finish();
	disconnectDB() if $disconnect;
	return $ver;
}

sub do_sql_file($) {
	my $file = shift;
	open ((my $SQL), $file) or die "$file: $!\n";
	my $sql;

	while(my $x = <$SQL>) {
		unless($x =~ /^#/ or $x eq $/) {
			$sql .= "$x$/";
		}
	}
	foreach my $line (split(/;/s, $sql)) {
		$dbh->do($line);
	}
}

1;
