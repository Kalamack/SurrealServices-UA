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

package SrSv::SimpleHash;

use strict;

use Exporter 'import';
BEGIN { our @EXPORT_OK = qw(read_hash readHash write_hash writeHash) }

sub writeHash {
	my $hash = $_[0];
	my $file = $_[1];

	my $fh;
	open $fh, '>', $file;

	my @keys = keys(%$hash); my @values = values(%$hash);

	for(my $i=0; $i<@keys; $i++) {
		if(ref($values[$i]) eq 'ARRAY') {
			chomp $keys[$i];
			print $fh $keys[$i], " =[ ";
			foreach my $atom (@{$values[$i]}) {
				print $fh $atom, ", ";
			}
			print $fh "\n";
		} else {
			chomp $keys[$i]; chomp $values[$i];
			print $fh $keys[$i], " = ", $values[$i], "\n";
		}
	}

	close $fh;
}

sub readHash {
	my $file = $_[0];
	my %hash;

	my $fh;
	open $fh, $file
		or die "ERROR: Unable to open config file $file: $!\n";

	while(my $line = <$fh>) {
		if($line =~ /^#|^\s*$/) { }
		elsif($line =~ /^(\S+) ?= ?\[ ?(.*) ?]$/) {
			my ($key, $value) = ($1, $2);
			chomp $key; chomp $value;
			$key =~ s/(^\s+|\s+$)//g;
			$value =~ s/(^\s+|\s+$)//g;
			$hash{$key} = [ split(/, /, $value) ];
		}
		elsif($line =~ /^\S+ ?= ?/) {
			my ($key, $value) = split(/ ?= ?/, $line, 2);
			chomp $key; chomp $value;
			if($value eq 'undef') {
				$value = undef;
			}
			$key =~ s/(^\s+|\s+$)//g;
			$value =~ s/(^\s+|\s+$)//g;
			$hash{$key} = $value;
		}
		else {
			die "Malformed config file: $file\n";
		}
	}
	close $fh;

	return (%hash);
}

BEGIN { # The same functions, now with less camelCase
	*write_hash = \&writeHash;
	*read_hash = \&readHash;
}

1;
