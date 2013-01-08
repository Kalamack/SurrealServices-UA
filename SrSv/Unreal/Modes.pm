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

package SrSv::Unreal::Modes;

use strict;

use Exporter 'import';
BEGIN { our @EXPORT_OK = qw(@opmodes %opmodes $scm $ocm $acm sanitize_mlockable) }

our @opmodes = ('v', 'h', 'o', 'a', 'q');
our %opmodes = (
	v => 1,
	h => 2,
	o => 4,
	a => 8,
	q => 16
);

# Channel modes with arguments:
our $scm = qr/^[bevhoaqI]$/;

# Channel modes with only one setting:
our $ocm = qr/^[kfLlj]$/;

# Allowed channel modes:
our $acm = qr/^[cfijklmnprstzACGIMKLNOQRSTVu]$/;

sub sanitize_mlockable($) {
	my ($inModes, @inParms) = split(/ /, $_[0]);
	my ($outModes, @outParms);

	my $sign = '+';
	foreach my $mode (split(//, $inModes)) {
		if ($mode =~ /[+-]/) {
			$sign = $mode;
			$outModes .= $mode;
			next;
		}
		my $parm = shift @inParms
			if (($mode =~ $ocm or $mode =~ $scm) and $sign eq '+');

		if ($mode =~ $scm) {
			next;
		} else {
			$outModes .= $mode;
			push @outParms, $parm if $parm;
		}
	}

	return $outModes . ' ' . join(' ', @outParms);
}

1;
