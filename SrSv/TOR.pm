#!/usr/bin/perl

#       This file is part of SurrealServices.
#
#       SurrealServices is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#
#       SurrealServices is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with SurrealServices; if not, write to the Free Software
#       Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

=pod
	Parses the TOR router list for exit-nodes, and optionally
	for exit-nodes that can connect to our services.

	Interface still in progress.
=cut

package SrSv::TOR;
use strict;

use Exporter 'import';
BEGIN { our @EXPORT = qw( getTorRouters ); }

sub openURI($) {
	my ($URI) = @_;
	my $fh;
	if($URI =~ s/^file:\/\///i) {
		use IO::File;
		$fh = IO::File->new($URI, 'r') or die;
	} else {
	# assume HTTP/FTP URI
		use IO::Pipe;
		$fh = IO::Pipe->new();
		$fh->reader(qq(wget -q -O - $URI)) or die;
	}
	return $fh;
}

our %TOR_cmdhash;
BEGIN {
%TOR_cmdhash = (
	'r'		=> \&TOR_r,
	's'		=> \&TOR_s,
	'router'	=> \&TOR_router,
	'reject'	=> \&TOR_reject,
	'accept'	=> \&TOR_accept,
);
}

sub parseTorRouterList($) {
	my ($fh) = @_;
	our (%currentRouter, @routerList);
	foreach my $l (<$fh>) {
		my ($tok, undef) = split(' ', $l, 2);
		#print "$l";
		chomp $l;
		if(my $code = $TOR_cmdhash{$tok}) {
			&$code($l);
		}
	}
	sub TOR_r {
		my ($l) = @_;
		#r atari i2i65Qm8DXfRpHVk6N0tcT0fxvs djULF2FbASFyIzuSpH1Zit9cYFc 2007-10-07 00:19:17 85.31.187.200 9001 9030
		my (undef, $name, undef, undef, undef, $ip, $in_port, $dir_port) = split(' ', $l);
		%currentRouter = ( NAME => $name, IP => $ip, IN_PORT => $in_port, DIR_PORT => $dir_port );
		return;
	}
	sub TOR_s {
		my ($l) = @_;
		if($l =~ /^s (.*)/) {
		#s Exit Fast Guard Stable Running V2Dir Valid
			my $tokens = $1;
			# uncomment the conditional if you trust the router status flags
			#if($tokens =~ /Exit/) {
				push @routerList, $currentRouter{IP};
			#}
		}
	}
	sub TOR_router {
		my ($l) = @_;
		my (undef, $name, $ip, $in_port, undef, $dir_port) = split(' ', $l);
		push @routerList, processTorRouter(%currentRouter) if scalar(%currentRouter);
		%currentRouter = ( NAME => $name, IP => $ip, IN_PORT => $in_port, DIR_PORT => $dir_port );
		return;
	}
	sub TOR_reject {
		my ($l) = @_;
		my ($tok, $tuple) = split(' ', $l);
		my ($ip, $ports) = split(':', $tuple);
		push @{$currentRouter{REJECT}}, "$ip:$ports";
	}
	sub TOR_accept {
		my ($l) = @_;
		my ($tok, $tuple) = split(' ', $l);
		my ($ip, $ports) = split(':', $tuple);
		push @{$currentRouter{ACCEPT}}, "$ip:$ports";
	}
	#close $fh;
	return @routerList;
}

sub processTorRouter(%) {
# only used for v1, and possibly v3
	my (%routerData) = @_;
	my @rejectList = ( $routerData{REJECT} and scalar(@{$routerData{REJECT}}) ? @{$routerData{REJECT}} : () );
	my @acceptList = ( $routerData{ACCEPT} and scalar(@{$routerData{ACCEPT}}) ? @{$routerData{ACCEPT}} : () );
	return () if $routerData{IP} =~ /^(127|10|192\.168)\./;
	if ( (scalar(@rejectList) == 1) and ($rejectList[0] eq '*:*') ) {
		#print STDERR "$routerData{IP} is not an exit node.\n";
		return ();
	} else {
		#print STDERR "$routerData{IP} is an exit node.\n";
		return ($routerData{IP});
	}
}

sub getTorRouters($) {
	my ($URI) = @_;
	return parseTorRouterList(openURI($URI));
}

1;
