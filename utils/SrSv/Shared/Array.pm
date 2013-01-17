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

package SrSv::Shared::Array;

=head1 NAME

SrSv::Shared::Array - Used internally by SrSv::Shared.

=cut

use strict;
no strict 'refs';

use SrSv::Process::InParent qw(STORE FETCH FETCHSIZE STORESIZE CLEAR PUSH POP SHIFT UNSHIFT SPLICE);

sub TIEARRAY {
	my ($class, $name) = @_;

	return bless \$name, $class;
}

sub STORE {
	my ($self, $key, $value) = @_;

	print "Store \@" . $$self . "\n" if SrSv::Shared::DEBUG;
	return ${$$self}[$key] = $value;
}

sub FETCH {
	my ($self, $key) = @_;

	print "Fetch \@" . $$self . "\n" if SrSv::Shared::DEBUG;
	return ${$$self}[$key];
}

sub FETCHSIZE {
	my ($self) = @_;

	return scalar @{$$self};
}

sub STORESIZE {
	my ($self, $value) = @_;

	return $#{$$self} = $value-1;
}

sub CLEAR {
	my ($self) = @_;

	return @{$$self} = ();
}

sub PUSH {
	my $self = shift;
	return push @{$$self}, @_;
}

sub POP {
	my ($self) = @_;

	return pop @{$$self};
}

sub SHIFT {
	my ($self) = @_;

	return shift @{$$self};
}

sub UNSHIFT {
	my $self = shift;
	return unshift(@{$$self}, @_);
}

sub SPLICE {
	my $self = shift;
	return splice(@{$$self}, @_);
}

1;
