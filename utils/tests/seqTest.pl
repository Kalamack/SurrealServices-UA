#!/usr/bin/perl

use strict;

BEGIN {
	use Cwd qw( abs_path getcwd );
	use File::Basename qw( dirname );
	use constant { PREFIX => abs_path(dirname(abs_path($0)).'/../') }
}
use lib PREFIX;

use libs::misc;
use SrSv::Util qw(say seqifyList makeSeqList);

#say makeSeqList(92..99,1..3,5..9,);
#say seqifyList(92..99,1..3,5..9,);
say seqifyList(makeSeqList(92..99,1..3,5..9,10,11));
