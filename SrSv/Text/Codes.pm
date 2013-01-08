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

package SrSv::Text::Codes;

use strict;

use Exporter 'import';
BEGIN { our @EXPORT_OK = qw(strip_codes) }

sub strip_codes(@) {
	my (@in) = @_;
	foreach my $string (@in) {
		$string =~ s/\003[0-9]{1,2}(?:,[0-9]{1,2})?|[[:cntrl:]]//g;
	}
	return (wantarray ? @in : $in[0]);
}

1;
