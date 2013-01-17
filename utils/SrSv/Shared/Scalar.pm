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

package SrSv::Shared::Scalar;

=head1 NAME

SrSv::Shared::Scalar - Used internally by SrSv::Shared.

=cut

use strict;
no strict 'refs';

use SrSv::Process::InParent qw(STORE FETCH);

sub TIESCALAR {
	my ($class, $name) = @_;

	return bless \$name, $class;
}

sub STORE {
	my ($self, $value) = @_;

	print "Store \$" . $$self . "\n" if SrSv::Shared::DEBUG;
	return ${$$self} = $value;
}

sub FETCH {
	my ($self) = @_;

	print "Fetch \$" . $$self . "\n" if SrSv::Shared::DEBUG;
	return ${$$self};
}

1;
