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

package SrSv::Process::Worker;

use strict;

use Carp 'croak';

use Exporter 'import';
BEGIN {
	our @EXPORT_OK = qw(spawn write_pidfiles
		ima_worker $ima_worker
		multi get_socket
		call_in_parent call_all_child do_callback_in_child
		shutdown_worker shutdown_all_workers kill_all_workers)
	}

use Event;
use English qw( -no_match_vars );
use IO::Socket;
use IO::File;
use Storable qw(fd_retrieve store_fd);

use SrSv::Debug;

sub PREFIX() { return main::PREFIX }

BEGIN {
	if(DEBUG) {
		require Data::Dumper; import Data::Dumper ();
	}
}

use SrSv::Message qw(message call_callback unit_finished);
use SrSv::Process::Call qw(safe_call);
use SrSv::RunLevel qw(:levels $runlevel);

use SrSv::Process::InParent qw(shutdown_worker shutdown_all_workers kill_all_workers);

use SrSv::Process::Init ();

our $parent_sock;
our $multi = 0;
our @workers;
our @free_workers;
our @queue;

our $ima_worker = 0;

### Public interface ###

sub spawn() {
	$multi = 1;

	my ($parent, $child) = IO::Socket->socketpair(AF_UNIX, SOCK_STREAM, PF_UNSPEC);

	if(my $pid = fork()) {
		my $worker = {
			SOCKET => $child,
			NUMBER => scalar(@workers),
			PID => $pid,
		};

		my $nr = @workers;
		push @workers, $worker;
		$worker->{WATCHER} = Event->io (
			cb => \&SrSv::Process::Worker::req_from_child,
			fd => $child,
			data => $nr,
		);
	} else {
		loop($parent);
		exit;
	}
}

sub write_pidfiles() {
	my $fh = IO::File->new("@{[PREFIX]}/data/worker.pids", 'w', '0600');
	for(my $i = scalar(@workers); $i; $i--) {
		my $pid = $workers[$i-1]->{PID};
		print $fh $pid,"\n";
	}
	print $fh $PID,"\n";
}

sub ima_worker {
	return $ima_worker;
}

sub multi {
	return $multi;
}

sub get_socket {
	if(ima_worker) {
		return $parent_sock;
	}
}

sub call_in_parent(@) {
	my ($f, @args) = @_;
	if(!ima_worker) {
		no strict 'refs';
		return &$f(@args);
	}

	my %call = (
		CLASS => 'CALL',
		FUNCTION => $f,
		ARGS => \@args
	);

	store_fd(\%call, $parent_sock);

	if(wantarray) {
		return @{ fd_retrieve($parent_sock) };
	} else {
		return @{ fd_retrieve($parent_sock) }[-1];
	}
}

sub call_all_child(@) {
	croak "call_all_child is not functional.\n";

=for comment
	my (@args) = @_;

	foreach my $worker (@workers) {
		store_fd(\@args, $worker->{SOCKET});
	}
=cut
}

{
	my $callback;

	sub shutdown_worker($) {
		my $worker = shift;

		print "Shutting down worker $worker->{NUMBER}\n" if DEBUG;
		store_fd({ _SHUTDOWN => 1 }, $worker->{SOCKET});
		$worker->{WATCHER}->cancel; undef $worker->{WATCHER};
		$worker->{SOCKET}->close; undef $worker->{SOCKET};
		undef($workers[$worker->{NUMBER}]);

		unless(grep defined($_), @workers) {
			print "All workers shut down.\n" if DEBUG;
			$callback->() if $callback;
		}
	}

	sub shutdown_all_workers($) {
		$callback = shift;

		while(my $worker = pop @free_workers) {
			shutdown_worker($worker);
		}
	}
}

sub kill_all_workers() {
	kill 9, map($_->{PID}, @workers);
}

### Semi-private Functions ###

sub do_callback_in_child {
	my ($callback, $message) = @_;

	# this whole thing is a workaround for perl 5.12's Storable.
	# Can't pass a regexp through Storable.
	if(ref($callback->{TRIGGER_COND}->{DST}) || ref($callback->{TRIGGER_COND}->{SRC})) {
		foreach my $k (qw(DST SRC)) {
			next unless defined $callback->{TRIGGER_COND}->{$k};
			my $v = $callback->{TRIGGER_COND}->{$k};
			$v = "$v"; # convert regexp to string
			$callback->{TRIGGER_COND}->{$k} = $v;
		}
		#use Data::Dumper;
		#ircd::debug( split($/, Data::Dumper::Dumper($worker->{UNIT})) );
	}
	if(my $worker = pop @free_workers) {
		print "Asking worker ".$worker->{NUMBER}." to call ".$callback->{CALL}."\n" if DEBUG;
		#store_fd([$unit], $worker->{SOCKET});
		$worker->{UNIT} = [$callback, $message];

		store_fd($worker->{UNIT}, $worker->{SOCKET});
	} else {
		push @queue, [$callback, $message];
		print "Added to queue, length is now" . @queue if DEBUG;
	}
}

### Internal Functions ###

sub req_from_child($) {
	my $event = shift;
	my $nr = $event->w->data;
	my $worker = $workers[$nr];
	my $fd = $worker->{SOCKET};

	my $req = eval { fd_retrieve($fd) };
	die "Couldn't read the request: $@" if $@;

	print "Got a ".$req->{CLASS}." message from worker ".$worker->{NUMBER}."\n" if DEBUG;

	if($req->{CLASS} eq 'CALL') {
		my @reply = safe_call($req->{FUNCTION}, $req->{ARGS});
		store_fd(\@reply, $fd);
	}
	elsif($req->{CLASS} eq 'FINISHED') {
		my $unit = $worker->{UNIT};
		$worker->{UNIT} = undef;

		print "Worker ".$worker->{NUMBER}." is now finished.\n" if DEBUG;

		if($runlevel == ST_SHUTDOWN) {
			shutdown_worker($worker);
			return;
		}

		push @free_workers, $worker;

		if(@queue) {
			print "About to dequeue, length is now " . @queue if DEBUG;
			do_callback_in_child(@{ shift @queue });
		}

		unit_finished($unit->[0], $unit->[1]);
	}
	elsif($runlevel != ST_SHUTDOWN) {
		store_fd({ACK => 1}, $fd);
		message($req);
	}
}

sub do_exit() {
	print "Worker ".@workers." shutting down.\n" if DEBUG;
	$parent_sock->close;
	exit;
}

sub loop($) {
	my ($parent) = @_;

	$ima_worker = 1;
	$parent_sock = $parent;

	SrSv::Process::Init::do_init();
	module::begin();

	store_fd({ CLASS => 'FINISHED' }, $parent);

	while(my $unit = fd_retrieve($parent)) {
		if(ref $unit eq 'HASH' and $unit->{_SHUTDOWN}) {
			do_exit;
		}
		print "Worker ".@workers." is now busy.\n" if DEBUG;
		call_callback(@$unit);

		print "Worker ".@workers." is now free.\n" if DEBUG;
		store_fd({ CLASS => 'FINISHED' }, $parent);
	}

	die "Lost contact with the mothership";
}

1;
