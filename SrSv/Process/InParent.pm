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

package SrSv::Process::InParent;

use strict;

use Filter::Util::Call;

use SrSv::Debug;
use SrSv::Process::Worker qw($ima_worker);

sub import {
	my $class = shift;
	my ($package) = caller;

	my $expr = join('|', @_);
	filter_add( sub {
		my $status;

		s/^sub ($expr)(\W|$)/sub $1\_INPARENT$2/ if ($status = filter_read()) > 0;
		print "Filtered: $_" if DEBUG() and $1;

		return $status;
	});

	my @subs = map { "$package\::$_" } @_;

	foreach my $sub (@subs) {
		no strict 'refs';
		no warnings;

		print "Installing stub for $sub\n" if DEBUG();
		*{$sub} = _make_stub($sub);
	}
}

sub _make_stub($) {
	my ($fake_sub) = @_;
	my $real_sub = \&{"$fake_sub\_INPARENT"};

	return sub {
		if($ima_worker) {
			print "Called $fake_sub in child.\n" if DEBUG();
			SrSv::Process::Worker::call_in_parent($fake_sub, @_);
		} else {
			print "Called $fake_sub in parent.\n" if DEBUG();
			goto &$real_sub;
		}
	};
}

1;
