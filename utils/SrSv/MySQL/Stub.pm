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

package SrSv::MySQL::Stub;

=head1 NAME

SrSv::MySQL::Stub - Create functions for SQL queries

=cut

use strict;

use Symbol 'delete_package';
use Carp qw( confess );

use SrSv::Debug;
use SrSv::MySQL qw( $dbh :sql_types );
use SrSv::Process::Init;

our %types;

sub create_null_stub($) {
	my ($stub) = @_;

	my $sth;

	proc_init {
		$sth = $dbh->prepare($stub->{SQL});
	};

	return sub {
		my $ret;
		eval { $ret = $sth->execute(@_) + 0; }; #force result to be a number
		if($@) { confess($@) }
		$sth->finish();
		return $ret;
	};
}

sub create_insert_stub($) {
	my ($stub) = @_;

	my $sth;

	proc_init {
		$sth = $dbh->prepare($stub->{SQL});
		# This is potentially interesting here,
		# given a INSERT SELECT
		if($stub->{SQL} =~ /OFFSET \?$/) {
			my @dummy = $stub->{SQL} =~ /\?/g;
			$sth->bind_param(scalar(@dummy), 0, SQL_INTEGER);
		}
	};

	return sub {
		eval { $sth->execute(@_) + 0 }; #force result to be a number
		if($@) { confess($@) }
		$sth->finish();
		return $dbh->last_insert_id(undef, undef, undef, undef);;
	};
}

sub create_scalar_stub($) {
	my ($stub) = @_;

	my $sth;

	proc_init {
		$sth = $dbh->prepare($stub->{SQL});
		if($stub->{SQL} =~ /OFFSET \?$/) {
			my @dummy = $stub->{SQL} =~ /\?/g;
			$sth->bind_param(scalar(@dummy), 0, SQL_INTEGER);
		}
	};

	return sub {
		eval{ $sth->execute(@_); };
		if($@) { confess($@) }
		my $scalar;
		eval{ ($scalar) = $sth->fetchrow_array; };
		if($@) { confess($@) }
		$sth->finish();
		return $scalar;
	};
}

sub create_arrayref_stub($) {
	my ($stub) = @_;

	my $sth;

	proc_init {
		$sth = $dbh->prepare($stub->{SQL});
		if($stub->{SQL} =~ /OFFSET \?$/) {
			my @dummy = $stub->{SQL} =~ /\?/g;
			$sth->bind_param(scalar(@dummy), 0, SQL_INTEGER);
		}
	};

	return sub {
		eval{ $sth->execute(@_); };
		if($@) { confess($@) }
		return $sth->fetchall_arrayref;
	};
}

sub create_array_stub($) {
	my ($stub) = @_;

	my $sth;

	proc_init {
		$sth = $dbh->prepare($stub->{SQL});
		if($stub->{SQL} =~ /OFFSET \?$/) {
			my @dummy = $stub->{SQL} =~ /\?/g;
			$sth->bind_param(scalar(@dummy), 0, SQL_INTEGER);
		}
	};

	return sub {
		eval{ $sth->execute(@_); };
		if($@) { confess($@) }
		my $arrayRef;
		eval{ $arrayRef = $sth->fetchall_arrayref; };
		if($@) { confess($@) }
		$sth->finish();
		return @$arrayRef;
	};
}

sub create_column_stub($) {
	my ($stub) = @_;

	my $sth;

	proc_init {
		$sth = $dbh->prepare($stub->{SQL});
=cut
# This isn't useful here.
		if($stub->{SQL} =~ /OFFSET \?$/) {
			my @dummy = $stub->{SQL} =~ /\?/g;
			$sth->bind_param(scalar(@dummy), 0, SQL_INTEGER);
		}
=cut
	};

	return sub {
		eval{ $sth->execute(@_); };
		if($@) { confess($@) }
		my $arrayRef;
		eval { $arrayRef = $sth->fetchall_arrayref; };
		if($@) { confess($@) }
		$sth->finish();
		return map({ $_->[0] } @$arrayRef);
	};
}

sub create_row_stub($) {
	my ($stub) = @_;

	my $sth;

	proc_init {
		$sth = $dbh->prepare($stub->{SQL});
		if($stub->{SQL} =~ /OFFSET \?$/) {
			my @dummy = $stub->{SQL} =~ /\?/g;
			$sth->bind_param(scalar(@dummy), 0, SQL_INTEGER);
		}
	};

	return sub {
		$sth->execute(@_);
		my @row = $sth->fetchrow_array;
		$sth->finish();
		return @row;
	};
}

BEGIN {
	%types = (
		NULL => \&create_null_stub,
		SCALAR => \&create_scalar_stub,
		ARRAYREF => \&create_arrayref_stub,

		ARRAY => \&create_array_stub,
		ROW => \&create_row_stub,
		COLUMN => \&create_column_stub,
		INSERT => \&create_insert_stub,
	);
}

sub export_stub($$$) {
	my ($name, $proto, $code) = @_;

	no strict 'refs';

	*{$name} = eval "sub $proto { goto &\$code }";
}

sub import {
	my (undef, $ins) = @_;

	while(my ($name, $args) = each %$ins) {
		my $stub = {
			NAME => $name,
			TYPE => $args->[0],
			SQL => $args->[1],
		};

		my @params = $stub->{SQL} =~ /\?/g;

		$stub->{PROTO} = '(' . ('$' x @params) . ')';
		print "$stub->{NAME} $stub->{PROTO}\n" if DEBUG;

		export_stub scalar(caller) . '::' . $stub->{NAME}, $stub->{PROTO}, $types{$stub->{TYPE}}->($stub);
	}
}

1;

=head1 SYNOPSIS

 use SrSv::MySQL::Stub {
	get_all_foo => ['ARRAYREF', "SELECT * FROM foo"],
	is_foo_valid => ['SCALAR', "SELECT 1 FROM foo WHERE id=? AND valid=1"],
	delete_foo => ['NULL', "DELETE FROM foo WHERE id=?"],

	get_all_foo_array => ['ARRAY', "SELECT * FROM foo"],
	get_column_foo => ['COLUMN', "SELECT col FROM foo"],
	get_row_foo => ['ROW', "SELECT * FROM foo LIMIT 1"],
	insert_foo > ['INSERT', "INSERT INTO foo (foo,bar) VALUES (?,?)"],
 };

=head1 DESCRIPTION

This module is a convenient way to make lots of subroutines that execute
SQL statements.

=head1 USAGE

  my @listOfListrefs = get_all_foo_array(...);
  my $listrefOfListrefs = get_all_foo(...);
  my $scalar = is_foo_valid(...);
  my $success = delete_foo(...);

type ARRAYREF is for legacy code only, I doubt anyone will want to use
it for new code. ARRAY returns a list of listrefs, while ARRAYREF
returns a listref of listrefs.

NULL returns success or failure. Technically, number of columns
affected. Thus sometimes it may not have FAILED, but as it had no
effect, it will return zero.

INSERT returns the last INSERT ID in the current execution context. This
basically means that if your table has a PRIMARY KEY AUTO_INCREMENT, it
will return the value of that primary key.

COLUMN returns a list consisting of a single column (the first, if there
are more than one in the SELECT).

ROW is like column, but returns an array of only a single row.

=cut
