#       This file is part of SurrealServices.
#
#       SurrealServices is free software; you can redistribute it and/or modify
#       it under the terms of the GNU Lesser General Public License as published
#       by the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#
#       SurrealServices is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU Lesser General Public License
#       along with SurrealServices; if not, write to the Free Software
#       Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package SrSv::Conf2Consts;

use strict;

use Carp 'croak';

use SrSv::SimpleHash qw(read_hash);
use SrSv::Conf::Parameters ();

#use SrSv::Util qw( PREFIX CWD );
# This is in main
BEGIN {
	*CWD = \&main::CWD;
	*PREFIX = \&main::PREFIX;
}

=head1 NAME

Util::Conf2Consts

=head1 DESCRIPTION

Given a file full of key=value pairs, produce constant functions for the
key that contains value.

=head1 SYNOPSIS

use Util::Conf2Consts ( main sql );

which will load the files main.conf and sql.conf, and load them into
your namespace.

=cut

our (%files, %defaults);

*defaults = \%SrSv::Conf::Parameters::params;

sub canonical($) {
	my $key = shift;
	$key =~ tr/-/_/;
	$key = lc $key;
}

sub make_const($) {
	my $x = shift;
	return sub() { $x };
}

sub get_file($) {
	my ($file) = @_;

	return $files{$file}
	# We cache the config so we only load the files once.
		if exists $files{$file};
	croak qq{Tried to use unknown conf file "$file"} unless $defaults{$file};

	my $data = {};
	{
		my %in_data = read_hash(PREFIX . "/config/$file.conf");
		foreach (keys %in_data) {
			$data->{canonical($_)} = $in_data{$_};
		}
	}

	my %known_params;

	foreach my $default (@{$defaults{$file}}) {
		my $key;

		if(ref $default) {
			($key, my $value) = @$default;
			
			$data->{$key} = $value
			# initialize value from default value (SrSv::Parameters::Conf)
			# unless we have a value from the config-file
				unless exists $data->{$key}; 
		}
		else {
			$key = $default;
			die qq{ERROR: Configuration file $file.conf must contain a "$key" setting.\n\n}
				unless exists $data->{$key};
		}
	
		$known_params{$key} = 1;
	}

	foreach my $key (keys %$data) {
		if($known_params{$key}) {
			$data->{$key} = make_const $data->{$key};
		}
		else {
			warn qq{Warning: Unknown setting "$key" in configuration file $file.conf\n};
			delete $data->{$key};
		}
	}

	return ($files{$file} = $data);
}

sub install_vars($$$) {
	no strict 'refs';
	no warnings;
	my ($pkg, $file, $data) = @_;

	while(my ($key, $value) = each %$data) {
		*{"${pkg}\::${file}_conf_${key}"} = $value;
	}
}

sub import {
	my ($pkg, @files) = @_;

	foreach my $file (@files) {
		install_vars caller, $file, get_file $file;
	}
}

1;
