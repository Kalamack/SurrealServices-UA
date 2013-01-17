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

package SrSv::MySQL::KeyValStub;

use strict;

use Symbol 'delete_package';

use SrSv::MySQL '$dbh';
use SrSv::Process::Init;

sub create_stub($$) {
	my ($get_sql, $set_sql) = @_;

	my ($get, $set);

	proc_init {
		$get = $dbh->prepare($get_sql);
		$set = $dbh->prepare($set_sql);
	};

	return sub ($;$) {
		my ($k, $v) = @_;

		if(defined($v)) {
			$set->execute($v, $k); $set->finish;
		} else {
			$get->execute($k);
			$v = $get->fetchrow_array;
			$get->finish;
		}

		return $v;
	};
}

sub create_readonly_stub($) {
	my ($get_sql) = @_;

	my ($get);

	proc_init {
		$get = $dbh->prepare($get_sql);
	};

	return sub ($) {
		my ($k) = @_;

		$get->execute($k);
		my $v = $get->fetchrow_array;
		$get->finish;

		return $v;
	};
}

sub import {
	my (undef, $stubs) = @_;

	my $callpkg = caller();

	while(my ($name, $sql) = each %$stubs) {
		no strict 'refs';

		my $stub;

		if(@$sql == 2) {
			$stub = create_stub($sql->[0], $sql->[1]);
		}
		elsif(@$sql == 1) {
			$stub = create_readonly_stub($sql->[0]);
		}
		else {
			my ($package, $filename, $line) = caller();
			die "Invalid use of ".__PACKAGE__." at $filename line $line\n";
		}

		*{"$callpkg\::$name"} = $stub;
	}
}

INIT {
	delete_package(__PACKAGE__);
}

1;
