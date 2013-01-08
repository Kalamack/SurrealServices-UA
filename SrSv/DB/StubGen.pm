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

Invid::DB::Stub - Create functions for SQL queries

=cut

package SrSv::DB::StubGen;

use strict;
use warnings;

require SrSv::DB::StubGen::Stub;

sub import {
	my $package = caller;

	shift @_; # Remove package name from arg list.
	my %stubhash = @_; # Basically we coerce the list back into a hash.
	my $generator = $stubhash{generator};
	my $dbh = $stubhash{dbh};
	my $sub = sub {
		import SrSv::DB::StubGen::Stub ($package, $dbh, @_);
	};

	# Export subroutine into caller's namespace.
	{
		no strict 'refs';
		*{"${package}::${generator}"} = $sub;
	}
}

__END__

=head1 SYNOPSIS

 use SrSv::DB::StubGen {
 	dbh => $dbh
 	generator => 'main_sql_stub',
 };

=head1 PURPOSE

The point of this is that although SrSv::DB::Stub is bloody useful, it
only lets you use one $dbh per program. What if you have more than one
database?

=head1 DESCRIPTION

See SrSv::DB::Stub for how you use the generator function.

However, instead of

use SrSv::DB::Stub ( ... )

one uses instead

main_sql_stub ( ... )

=cut
