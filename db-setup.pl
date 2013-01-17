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
use strict;

use Getopt::Long;

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
use lib PREFIX, "@{[PREFIX]}/CPAN";

our ($delete_db, $skip_backup, $auto_backup, $restore, $help);
BEGIN {
	GetOptions (
		"delete" => \$delete_db,
		"skip-backup" => \$skip_backup,
		"backup" => \$auto_backup,
		"restore" => \$restore,
		"help" => \$help,
	);

	if($help) {
		print qq"
Options:
	--delete	Delete entire database
	--skip-backup	Don't nag about making a backup
	--backup	Make backup without upgrading
	--restore FILE	Restore the database from a backup
	--help		Show this message
";

		exit 1;
	}
}

use SrSv::Conf qw(main sql);
use SrSv::DB::Schema;

BEGIN {
	if($restore) {
		my $f = shift @ARGV;
		$f or die "You must specify a backup file to restore.\n";
		print "Restoring from backup...\n";
		system("mysql $sql_conf{'mysql-db'} -u $sql_conf{'mysql-user'} --password=$sql_conf{'mysql-pass'} <$f");
		print "Finished.\n";
		exit;
	}
}

use SrSv::MySQL '$dbh';

use SrSv::Upgrade::HashPass;

my $backup_file;

sub ask($) {
	print shift;

	while(my $c = getc) {
		next unless $c =~ /\S/;
		return (lc $c eq 'y');
	}
}

unless($skip_backup) {
	if($auto_backup or ask "Would you like to make a backup of your database: $sql_conf{'mysql-db'}? (Y/n) ") {
		my @lt = localtime();
		$backup_file = "./db-backup-" . sprintf( "%04d%02d%02d", ($lt[5]+1900) , ($lt[4]+1) , ($lt[3]) ) . "-$$.sql";
		print "Creating backup in $backup_file\n";
		system("./utils/db-dump.pl > $backup_file");
		goto END if $auto_backup;
	}
}

if($delete_db) {
	exit unless ask "Really delete all data in database: $sql_conf{'mysql-db'}? (y/N) ";

	print "Deleting old tables...\n";

	my $table_list = $dbh->prepare("SHOW TABLES");
	$table_list->execute;
	while(my $t = $table_list->fetchrow_array) {
		$dbh->do("DROP TABLE $t");
	}
}

$dbh->{RaiseError} = 0;
$dbh->{PrintError} = 0;

my ($ver) = check_schema();
#print "$ver\n";
if($ver == 0) {
	print "Creating tables...\n";
	do_sql_file("sql/services.sql");
	upgrade_schema(0);
} elsif($ver) {
	upgrade_schema($ver);
}

print "Updating chanperm...\n";

my $add_perm = $dbh->prepare("INSERT IGNORE INTO chanperm SET name=?, level=?, max=?");
my $del_perm = $dbh->prepare("DELETE FROM chanperm WHERE name=?");

my @perms = (
	['Join', 0, 1],
	['AccList', 1, 0],
	['AccChange', 5, 0],
	['AKICK', 5, 0],
	['AKickList', 3, 0],
	['AKickEnforce', 5, 0],
	['SET', 6, 0],
	['BAN', 4, 0],
	['CLEAR', 6, 0],
	['GETKEY', 4, 0],
	['INFO', 0, 0],
	['KICK', 4, 0],
	['LEVELS', 6, 7],
	['LevelsList', 3, 7],
	['INVITE', 4, 0],
	['InviteSelf', 1, 0],
	['TOPIC', 5, 0],
	['UnbanSelf', 2, 0],
	['UNBAN', 4, 0],
	['VOICE', 2, 0],
	['HALFOP', 3, 0],
	['OP', 4, 0],
	['ADMIN', 5, 0],
	['OWNER', 6, 0],
	['Memo', 5, 0],
	['BadWords', 5, 0],
	['Greet', 1, 0],
	['NoKick', 4, 0],
	['BotSay', 5, 0],
	['BotAssign', 6, 0],
	['SetTopic', 0, 0],
	['WELCOME', 6, 0],
	['DICE', 1, 0],
	['UPDOWN', 1, 0],
	['MemoAccChange', 8, 0],
	['MODE', 6, 0],
	['COPY', 7, 0],
);

my @noperms = ();

foreach my $p (@perms) {
	$add_perm->execute($p->[0], $p->[1], $p->[2]);
}

foreach my $p (@noperms) {
	$del_perm->execute($p);
}

hash_all_passwords();

print "Database setup complete!\n";

END:
$backup_file and print "\nNOTE: To restore your backup, use this command:\n  ./db-setup.pl --restore $backup_file\n";
