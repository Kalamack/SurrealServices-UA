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

package SrSv::NickControl::Enforcer;

=head1 NAME

SrSv::NickControl::Enforcer - Prevent users from using nicks without identifying.

=head1 SYNOPSIS

 use SrSv::NickControl::Enforcer qw(%enforcers);

=head1 DESCRIPTION

At the moment, this is just a place to put the %enforcers hash.

=cut

use strict;

use Exporter 'import';
BEGIN { our @EXPORT_OK = qw(%enforcers) }

use SrSv::Shared qw(%enforcers);

1;
