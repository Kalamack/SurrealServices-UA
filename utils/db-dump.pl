#!/usr/bin/perl

########################################################################
#                                                                      #
# SurrealServices Database Dumper 0.2.3                                #
#                                                                      #
# This was written b/c the mysqldump program we had was broken.        #
# It will be made both stupid enough and generic enough that it may    #
# be used for other databases as well.                                 #
#                                                                      #
#  (C) Copyleft tabris@surrealchat.net 2005, 2006                      #
#   All rights reversed, All wrongs avenged.                           #
#                                                                      #
########################################################################

use strict;
use DBI;

# Add tables to this list to be skipped
# SrSv wants to skip the country table
our %skipList = ( 'country' => 1, 'geoip' => 1, 'geolocation' => 1, 'georegion' => 1, 'opm' => 1 );

use constant {
	DROP_TABLE => 1,
#	Default maximum packet size is 1MB
#	according to the documentation.
	MAX_PACKET => (512*1024), # 512KiB

	# Set to 1 if you have large tables, say over 32MB
	# Reduces memory requirements, but will probably be slower.
	# If set to zero, we fetch the entire table into memory
	# then dump it. 
	# WARNING: Doing this with hundred megabyte tables
	# will probably be slow, and possibly DoS your system
	# with an Out of Memory condition.
	LARGE_TABLES => 1,
	# Most of the time, you don't want to preserve the contents
	# of a MEMORY or HEAP table, since they're just temporary
	# and would have been lost on a server restart anyway.
	# Then again, maybe you want to keep them. If so, set this to 0.
	# This does still save the schema.
	SKIP_HEAP_DUMP => 0,

	# This should only be used for debugging purposes
	# as otherwise it throws junk into the output stream
	VERBOSE => 0,
};

our $dbh;
our $prefix;

BEGIN {
use Cwd qw( abs_path getcwd );
use File::Basename;
	$prefix = dirname(dirname(abs_path($0)).'../');
	chdir $prefix;
	import constant { PREFIX => $prefix, CWD => getcwd() };
}

# WARNING: for the generic case, this needs to be adapted
# Either adapt the config file that you use,
# or create a static hash table
sub get_sql_conn {
# These libs aren't needed for the generic case
use SrSv::Conf::sql;
use SrSv::Conf2Consts qw( sql );

	my %MySQL_config = (
		'mysql-db' => sql_conf_mysql_db,
		'mysql-user' => sql_conf_mysql_user,
		'mysql-pass' => sql_conf_mysql_pass
	);

	$dbh = DBI->connect(
		"DBI:mysql:".$MySQL_config{'mysql-db'},
		$MySQL_config{'mysql-user'},
		$MySQL_config{'mysql-pass'},
		{
			AutoCommit => 1,
			RaiseError => 1
		}
	);
}

sub get_schema($) {
	my ($table) = @_;
	my ($l, $column_data);
	my $get_table = $dbh->prepare("SHOW CREATE TABLE `$table`");
	$get_table->execute();
	my $result = $get_table->fetchrow_array;
	$get_table->finish();

	$l .= "\n--\n-- Table structure for table `$table`\n--\n".
			"$result;\n";
	my $get_column_info = $dbh->column_info(undef, undef, $table, '%');
	$get_column_info->execute();
	print "\n";
	while(my $column_info = $get_column_info->fetchrow_hashref()) {
		print '#'. $table.'.'.$column_info->{COLUMN_NAME} .'(column #'.$column_info->{ORDINAL_POSITION}.')' . ' is type '.$column_info->{TYPE_NAME}."\n" if VERBOSE;
		$column_data->[$column_info->{ORDINAL_POSITION}] = $column_info;
	}

	return ($l, $column_data);
}

sub prepare_output($$) {
	my ($table, $data) = @_;
	return "INSERT INTO `$table` VALUES ".$data.";\n";
}

sub get_data($$) {
	my ($table, $column_data) = @_;
	my @lines = ();

	# This is typically faster than a select loop
	# However, with REALLY BIG tables, it may become a DoS
	# Due to selecting too much data at once.
	my $results = $dbh->selectall_arrayref('SELECT * FROM '."`$table`");
	my $data = '';
	foreach my $row (@$results) {
		my $i = 0;
		foreach my $element (@$row) {
			if ($column_data->[++$i]->{TYPE_NAME} =~ /^(TEXT|BLOB)$/i and
				length($element))
			{
				$element = '0x' . unpack ('H*', $element);
			}
			elsif ($column_data->[$i]->{TYPE_NAME} =~ /int$/i and
				length($element))
			{
				# do nothing
			} else {
				$element = $dbh->quote($element);
			}
		}
		my $l = '('.join(',', @$row).')';
		if ((length($data) + length($l)) > MAX_PACKET) {
			push @lines, prepare_output($table, $data);
			$data = $l;
		} else {
			if(length($data)) {
				$data .= ",$l";
			} else {
				$data = $l;
			}
		}
	}

	push @lines, prepare_output($table, $data) if length($data);
	return @lines;
}

sub get_data_large($$) {
	my ($table, $column_data) = @_;

	my $data = '';
	my $query = $dbh->prepare('SELECT * FROM '."`$table`");
	$query->execute();
	while (my @row = $query->fetchrow_array) {
		my $i = 0;
		foreach my $element (@row) {
			if ($column_data->[++$i]->{TYPE_NAME} =~ /^(TEXT|BLOB)$/i and
			 	length($element))
			{
				$element = '0x' . unpack ('H*', $element);
			}
			elsif ($column_data->[$i]->{TYPE_NAME} =~ /int$/i and
				length($element))
			{
				# do nothing
			} else {
				$element = $dbh->quote($element);
			}
		}
		my $l = '('.join(',', @row).')';
		if ((length($data) + length($l)) > MAX_PACKET) {
			print prepare_output($table, $data);
			$data = $l;
		} else {
			if(length($data)) {
				$data .= ",$l";
			} else {
				$data = $l;
			}
		}
	}

	print prepare_output($table, $data) if length($data);
}

sub do_dump() {
	my $tables = $dbh->selectcol_arrayref("SHOW TABLES");

	TABLE: foreach my $table (@$tables) {
		print "DROP TABLE IF EXISTS `$table`;" if DROP_TABLE;
		my $column_data;

		{
			my $schema;
			($schema, $column_data) = get_schema($table);
			print $schema."\n";
			if ((SKIP_HEAP_DUMP) and 
			    (($schema =~ /(ENGINE|TYPE)=(HEAP|MEMORY)/)) or ($skipList{lc $table})
			) {
			    next TABLE;
			}
		}

		print "--\n-- Dumping data for table '$table'\n--\n".
			"LOCK TABLES `$table` WRITE;\n".
			"/*!40000 ALTER TABLE `$table` DISABLE KEYS */;\n";
		if(LARGE_TABLES) {
			get_data_large($table, $column_data);
		} else {
			print join("\n", get_data($table, $column_data));
		}
		print "/*!40000 ALTER TABLE `$table` ENABLE KEYS */;\n".
			"UNLOCK TABLES;\n".
			"\n";
	}
}

get_sql_conn();
do_dump();
exit 0;
