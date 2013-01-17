#!/usr/bin/perl
#       This file is part of SurrealServices.
#
#       SurrealServices is free software; you can redistribute it and/or modify
#       it under the terms of the GNU Lesser General Public License version 2.1,
#       as published by the Free Software Foundation.
#
#       SurrealServices is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU Lesser General Public License
#       along with SurrealServices; if not, write to the Free Software
#       Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


=cut

THIS CODE IS alpha only, and untested. Don't just trust it blindly.

=cut

use strict;
use warnings;
# the next 2 lines are temp, you should use the 3rd.
use UUID;
import SrSv::Insp::UUID qw( decodeUUID encodeUUID );
#use SrSv::Insp::UUID;

my $int = decodeUUID('751AAAAAA');
print "$int\n";
print log($int)/log(2), "\n";
encodeUUID($int);
