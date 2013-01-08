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

package SrSv::Timer;

use strict;

use Exporter 'import';
BEGIN { our @EXPORT_OK = qw(add_timer begin_timer stop_timer) }

use Event;

use SrSv::Debug;
use SrSv::Process::InParent qw(_add_timer stop_timer);
use SrSv::Message qw(message add_callback);

our @timers;
our $timer_watcher;

add_callback({
	TRIGGER_COND => { CLASS => 'TIMER' },
	CALL => 'SrSv::Timer::call',
});

if(DEBUG()) {
	add_timer('hello', 2, __PACKAGE__, 'SrSv::Timer::test');
	sub test { ircd::privmsg('ServServ', '#surrealchat', $_[0]) };
}

sub add_timer($$$$) {
	my ($token, $delay, $owner, $callback) = @_;

	if($callback !~ /::/) {
		$callback = caller() . "::$callback";
	}

	_add_timer($token, $delay, $owner, $callback);
}

sub _add_timer {
	my ($token, $delay, $owner, $callback) = @_;

	push @{ $timers[$delay] }, [$token, $owner, $callback];
}

sub begin_timer {
	$timer_watcher = Event->timer(interval => 1, cb => \&trigger);
}

sub stop_timer {
	$timer_watcher->cancel if $timer_watcher;
}

sub trigger {
	my $timers = shift @timers;
	
	foreach my $timer (@$timers) {
		message({
			CLASS => 'TIMER',
			TOKEN => $timer->[0],
			OWNER => $timer->[1],
			REALCALL => $timer->[2],
			CALL => 'SrSv::Timer::call'
		});
	}
}

sub call {
	no strict 'refs';
	my ($message, $callback) = @_;
	
	&{$message->{REALCALL}}($message->{TOKEN});
}

1;
