package SrSv::Constants;

use strict;

use Exporter 'import';
BEGIN {
	my $constants = {
		# Wait For
		WF_NONE		=> 0,
		WF_NICK		=> 1,
		WF_CHAN		=> 2,
		WF_ALL		=> 3,
		WF_MSG		=> 4,
		WF_MAX		=> 4,
	};
	require constant;
	import constant $constants;
	our @EXPORT = keys %$constants;
}

1;
