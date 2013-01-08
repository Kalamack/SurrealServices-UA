#!/usr/bin/perl

use strict;

BEGIN {
	use Cwd qw( abs_path getcwd );
	use File::Basename qw( dirname );
	use constant { PREFIX => abs_path(dirname(abs_path($0)).'/../') }
}
use lib PREFIX;

use SrSv::Time;

my ($weeks, $days, $hours, $minutes, $seconds) = split_time(103.2);

print "$minutes $seconds\n";
