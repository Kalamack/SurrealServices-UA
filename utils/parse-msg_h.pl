#!/usr/bin/perl

use strict;

my (%cmd_hash, %tok_hash);
my $debug = 0;

#open MSGH, "include/msg.h";
while (my $l = <STDIN>) {
	chomp $l;
	if ($l =~ /^#define(\s|\t)MSG_(\w+)(\s|\t)+\"(\S+)\".*/) {
		$cmd_hash{$2}->{MSG} = $4;
		print $l."\n" if $debug;
		print "$2 $4"."\n" if $debug;
	}
	elsif ($l =~ /^#define(\s|\t)TOK_(\w+)(\s|\t)+\"(\S+)\".*/) {
		$cmd_hash{$2}->{TOK} = $4;
		print $l."\n" if $debug;
		print "$2 $4"."\n" if $debug;
	}
}
#close MSGH;


foreach my $key (keys(%cmd_hash)) {
	my $tok = $cmd_hash{$key}{TOK};
	my $msg = $cmd_hash{$key}{MSG};
#	print $msg.' 'x(12-length($msg)). $tok."\n" if ($msg and $tok);
	$tok_hash{$tok} = $msg if ($msg and $tok);
}

for(my $l = 1; $l <= 2; $l++) {
	foreach my $key (sort keys %tok_hash) {
		print $tok_hash{$key}.' 'x(12-length($tok_hash{$key})). $key."\n" if length($key) == $l;
	}
}
