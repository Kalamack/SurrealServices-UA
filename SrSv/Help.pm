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
package SrSv::Help;
use strict;

use SrSv::User::Notice qw( notice );

use Exporter 'import';
BEGIN {
	our @EXPORT = qw( sendhelp readhelp );
	my %constants = ( HELP_PATH => main::PREFIX()."/help/" );
	require constant; import constant \%constants;
}

sub readhelp($) {
        my ($file_name) = @_;
        my @array;

        open ((my $file_handle), $file_name) or return undef();

        while(my $x = <$file_handle>) {
		next if $x =~ /^#/;
                chomp $x;
		$x =~ s/\%B/\002/g;
		$x =~ s/\%U/\037/g; # chr(31)
		$x =~ s/\%E(.*?)\%E/eval($1)/eg;

		$x = ' ' if $x eq '';
                push @array, $x;
        }

        close $file_handle;

        return (' ', @array, ' --');
}

sub sendhelp($@) {
	my ($user, @subject) = @_;
	
	@subject = split(/ /, $subject[0]) if(@subject == 1);
	
	# change any / or . to _
	# this is to prevent ppl from using this to access
	# files outside of the helpdir.
	# also lowercase the @subject components
	foreach my $s (@subject) {
		$s = lc $s;
		$s =~ s/[^a-z0-9\-]/_/g;
	}
	
        my $file = HELP_PATH . join('/', @subject) . '.txt';
	my @array = readhelp($file);
        unless($array[0]) {
	    notice($user, "No help for \002".join(' ', 
			@subject)."\002");
	    return;
	}

	notice($user, @array);
}

1;
