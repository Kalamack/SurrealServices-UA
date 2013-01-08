#!/usr/bin/perl

#       This file is part of SurrealServices.
#
#       SurrealServices is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#
#       SurrealServices is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with SurrealServices; if not, write to the Free Software
#       Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

use strict;
use File::stat;

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

use SrSv::Time;

my $logdir = PREFIX.'/logs';
my $chanlogdir = "$logdir/chanlogs";
my $gzip = qx(which gzip); 
my $bzip2 = qx(which bzip2);
chomp ($gzip, $bzip2);
# greater than 1000 bytes, bzip2, else gzip.
# This is based on an average observed from chanlogs.
# Thankfully bzcat and bzgrep tend to be agnostic.
my $bzip_threshold = 1000; 
# if less than 100 bytes, don't bother to gzip.
my $gzip_threshold = 100; 

opendir ((my $LOGDIR), $logdir.'/');

my $i = 0; my @today = gmt_date();
while (my $filename = readdir($LOGDIR)) {
	next if $filename eq '..' or $filename =~ /\.(gz|bz2)$/ or !(-f "$logdir/$filename");
	my $dir; my ($year, $month, $day);
	if($filename =~ /^services.log-(\d{4})-(\d{2})-(\d{2})$/i) {
		($year, $month, $day) = ($1, $2, $3);
		if($year == $today[0] and $month == $today[1] and $day == $today[3]) {
			# Don't process today's logs
			print "Skipping $filename\n";
			next;
		}

		$dir = $logdir;
	}
	elsif ($filename =~ /^#.*\.log-(\d{4})-(\d{2})-(\d{2})$/i) {
		($year, $month, $day) = ($1, $2, $3);
		if($year == $today[0] and $month == $today[1] and $day == $today[3]) {
			# Don't process today's logs
			print "Skipping $filename\n";
			next;
		}
		# Eventual plan is to make these available on the website...
		# This may necessitate only using gzip however (mod_deflate)
		
		$dir = $chanlogdir;
		mkdir $chanlogdir unless (-d $chanlogdir);

	}
	else { next; }
	# rename() is 'move', or really link($newname) and unlink($oldname)
	unless(-d "$dir/$year/$month") {
		mkdir "$dir/$year" unless (-d "$dir/$year");
		mkdir "$dir/$year/$month";
	}
	rename "$logdir/$filename", "$dir/$year/$month/$filename";
	compressFile("$dir/$year/$month/$filename");
	$i++;
}

sub compressFile($) {
	my ($file) = @_;
	my $fileStat = stat($file);
	my $fileSize = $fileStat->[7];
	my $compressor;
	if($fileSize > $bzip_threshold) {
		$compressor = $bzip2;
	} elsif($fileSize < $gzip_threshold) {
		return;
	} else {
		$compressor = $gzip;
	}
	system($compressor, '-9vv', $file);
}
closedir $LOGDIR;

print "Processed $i logs\n";
