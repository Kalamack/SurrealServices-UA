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

package SrSv::Shared;

=head1 NAME

SrSv::Shared - Share global variables among processes.

=cut

use strict;

use SrSv::Debug;

use SrSv::Process::Worker qw(ima_worker);
use SrSv::Process::Init;

use SrSv::Shared::Scalar;
use SrSv::Shared::Array;
use SrSv::Shared::Hash;

our @shared_vars;

sub import {
	croak("Shared variables can only be created by the parent process")
		if ima_worker;

	my $class = shift;
	my ($package) = caller;

	for (@_) {
		my $var = $_;
		my $sigil = substr($var, 0, 1, '');
		my $pkgvar = "$package\::$var";

		push @shared_vars, [$sigil, $pkgvar];

		# make the variable accessable in the parent.
		no strict 'refs';
		*$pkgvar = (
			$sigil eq '$' ? \$$pkgvar :
			$sigil eq '@' ? \@$pkgvar :
			$sigil eq '%' ? \%$pkgvar :
			croak("Only scalars, arrays, and hashes are supported")
		);
	}
}

proc_init {
	return unless ima_worker;
	no strict 'refs';
	
	for (@shared_vars) {
		my ($sigil, $var) = @$_;

		if($sigil eq '$') {
			tie ${$var}, 'SrSv::Shared::Scalar', $var;
		}
		elsif($sigil eq '@') {
			tie @{$var}, 'SrSv::Shared::Array', $var;
		}
		elsif($sigil eq '%') {
			tie %{$var}, 'SrSv::Shared::Hash', $var;
		}

		print "$sigil$var is now shared.\n" if DEBUG;
	}
};

1;

__END__

=head1 SYNOPSIS

 use SrSv::Shared qw($shared1 @shared2 %shared3);

=head1 DESCRIPTION

This module creates shared variables.

=head1 CAVEATS

Operations which iterate through an entire hash are not supported.  This
includes keys(), values(), each(), and assignment to list context.  If you need
to do these things, do them in the parent process. (See SrSv::Process::InParent)
