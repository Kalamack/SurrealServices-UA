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

package SrSv::RunLevel;

=head1 NAME

SrSv::RunLevel - Control system state.

=cut

use strict;

use Exporter 'import';

BEGIN {
	my %constants = (
		ST_NORMAL => 1,
		ST_SHUTDOWN => 2,
	);
	
	our @EXPORT_OK = (qw($runlevel main_shutdown emerg_shutdown), keys(%constants));
	our %EXPORT_TAGS = (levels => [keys(%constants)]);

	require constant; import constant (\%constants);
}

# FIXME: Uncommenting this breaks $ircd_ready for some reason.
#use SrSv::IRCd::IO qw(ircd_disconnect);
use SrSv::Process::Worker qw(ima_worker shutdown_all_workers kill_all_workers call_in_parent);
use SrSv::Timer 'stop_timer';

our $runlevel = ST_NORMAL;

sub main_shutdown() {
	call_in_parent(__PACKAGE__.'::_main_shutdown');
}

sub emerg_shutdown() {
	$runlevel = ST_SHUTDOWN;
	stop_timer;
	shutdown_all_workers sub { exit; };

	Event->timer(after => 5, cb => sub {
		kill_all_workers;

		exit;
	});
}

sub _main_shutdown() {
	ircd::agent_quit_all("Shutting down.");

	emerg_shutdown;
}

1;

__END__

=head1 SYNOPSIS

 use SrSv::RunLevel;
 
 main_shutdown;

