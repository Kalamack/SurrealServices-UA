#       This file is part of Invid
#
#       Invid is free software; you can redistribute it and/or
#       modify it under the terms of the GNU Lesser General Public
#       License version 2.1 as published by the Free Software Foundation.

#       This library is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#       Lesser General Public License for more details.

#       You should have received a copy of the GNU Lesser General Public
#       License along with this library; if not, write to the Free Software
#       Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

# Copyright Adam Schrotenboer <adam@tabris.net> 2007, 2008
#

# This code is based in large part on the MySQL::Stub from SrSv, as well as
# the DB::Sub from M2000's CMS.

=head1 NAME

SrSv::DB::StubGen::Stub - Create functions for SQL queries

=cut

package SrSv::DB::StubGen::Stub;
use strict;

use Carp qw( confess );

our %create_sub = (
	# For INSERT queries, returns last_insert_id.
	INSERT => sub($) {
		my $dbh = shift @_;
		my $q = shift;
		return sub {
			eval { $q->execute(@_); };
			if($@) { confess($@) }
			$q->finish();
			return $dbh->last_insert_id(undef, undef, undef, undef);
		}
	},

	# For UPDATE or DELETE queries; returns number of rows affected.
	NULL => sub ($) {
		my $dbh = shift @_;
		my $q = shift;
		return sub {
			my $ret;
			eval { $ret = $q->execute(@_) + 0; }; # Force it to be a number.
			if($@) { confess($@) }
			$q->finish();
			return ($ret);
		}
	},

	# For queries that return only one row with one columns; returns a scalar.
	SCALAR => sub ($) {
		my $dbh = shift @_;
		my $q = shift;
		return sub {
			eval { $q->execute(@_); };
			if($@) { confess($@) }
			my $scalar;
			eval { ($scalar) = $q->fetchrow_array; };
			if($@) { confess($@) }
			$q->finish();
			return $scalar;
		}
	},

	# For queries that return only one row with multiple columns; returns a 1-dimensional array.
	ROW => sub ($) {
		my $dbh = shift @_;
		my $q = shift;
		return sub {
			eval { $q->execute(@_); };
			if($@) { confess($@) }
			my @row;
			eval { @row = $q->fetchrow_array; };
			if($@) { confess($@) }

			$q->finish();
			return @row;
		}
	},

	# For queries that return just a single column, multiple rows
	# return a 1D array.
	COLUMN => sub ($) {
		my $dbh = shift @_;
		my $q = shift;
		return sub {
			eval { $q->execute(@_); };
			if($@) { confess($@) }
			my $arrayref;
			eval { $arrayref = $q->fetchall_arrayref() };
			if($@) { confess($@) }
			
			$q->finish();
			return map({ $_->[0] } @$arrayref);
		}
	},


	# For other queries; returns an arrayref.
	ARRAY => sub ($) {
		my $dbh = shift @_;
		my $q = shift;
		return sub {
			#die "improper number of parameters for $sth\n" unless $q->{NUM_OF_PARAMS} == scalar(@_);
			eval { $q->execute(@_); };
			if($@) { confess($@) }
			if ($q->err) { say ("ERROR: ", $q->err); }
			my $arrayref;
			eval { $arrayref = $q->fetchall_arrayref() };
			if($@) { confess($@) }
			
			$q->finish();
			return @$arrayref;
		}
	},

	ARRAYREF => sub ($) {
		my $dbh = shift @_;
		my $q = shift;
		return sub {
			$q->execute(@_);
			my $arrayref;
			eval { $arrayref = $q->fetchall_arrayref() };
			if($@) { confess($@) }
			$q->finish();
			return ($arrayref);
		}
	},
);

sub import {
	shift @_; # Remove most-recent-caller package name from arg list.

	# this is the _original_ package caller
	my $package = shift @_;
	my $dbh = shift @_;

	my $printError = $dbh->{PrintError};
	$dbh->{PrintError} = 1;

	foreach (@_) {
		my ($name, $type, $query) = @$_;
=cut
		$query =~ s/\n/ /gm;
		$query =~ s/\s{2,}/ /g;
		print "$query \n";
=cut
		# Prepare query
		my $q = $dbh->prepare($query);

		# Create subroutine.
		my $sub = $create_sub{$type}->($dbh, $q);

		# Export subroutine into caller's namespace.
		{
			no strict 'refs';
			*{"${package}::${name}"} = $sub;
		}
	}
	$dbh->{PrintError} = $printError;
}
