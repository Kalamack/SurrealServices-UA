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

package SrSv::Process::Call;

use strict;

use Exporter 'import';
BEGIN { our @EXPORT_OK = qw(safe_call) }

use Carp 'longmess';

sub safe_call($$) {
	my ($call, $parms) = @_;
	my $wa = wantarray;
	my $ret;

	eval {
		no strict 'refs';

		local $SIG{__WARN__} = sub {
			ircd::debug(" -- Warning: ".$_[0],
				($_[0] =~ /MySQL\/Stub/ ? split(/\n/, Carp::longmess($@)) : undef ) );
		};

		local $SIG{__DIE__} = sub {
			($_[0] =~ /^user/) or
				ircd::debug(" --", "-- DIED: ".$_[0], split(/\n/, Carp::longmess($@)), " --");
		};
			

		if(not defined($wa)) {
			&$call(@$parms);
		}
		elsif(not $wa) {
			$$ret = &$call(@$parms);
		}
		else {
			@$ret = &$call(@$parms);
		}
	};
	return undef if $@;

	if(not defined($wa)) {
		return;
	}
	elsif(not $wa) {
		return $$ret;
	}
	else {
		return @$ret;
	}
}

1;
