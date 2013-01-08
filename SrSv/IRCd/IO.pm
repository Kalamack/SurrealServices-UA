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

package SrSv::IRCd::IO;

use strict;

use Exporter 'import';
BEGIN { our @EXPORT_OK = qw(ircd_connect ircd_disconnect ircsendimm ircsend ircd_flush_queue ) }

use constant {
	NL => "\015\012",
};

use Errno ':POSIX';
use Event;
use SrSv::Conf 'main';
use SrSv::Process::InParent qw(irc_connect ircsend ircsendimm ircd_flush_queue);
use SrSv::Process::Worker qw(ima_worker);
use SrSv::Debug;
use SrSv::IRCd::State qw($ircline $ircline_real $ircd_ready);
use SrSv::IRCd::Event qw(callfuncs);
use SrSv::Unreal::Tokens qw( :tokens );
use SrSv::IRCd::Parse qw(parse_line);
use SrSv::RunLevel qw(emerg_shutdown);
use SrSv::Log qw( write_log );

our $irc_sock;
our @queue;
our $flood_queue;

sub irc_error($) {
	print "IRC connection failed", ($_[0] ? ": $_[0]\n" : ".\n");
	emerg_shutdown;
}

{
	my $partial;

	sub ircrecv {
		my ($in, $r);
		while($r = $irc_sock->sysread(my $part, 4096) > 0) {
			$in .= $part;
		}

		irc_error($!) if($r <= 0 and not $!{EAGAIN});

		my @lines = split(/\015\012/, $in);

		$lines[0] = $partial . $lines[0];
		if($in =~ /\015\012$/s) {
			$partial = '';
		} else {
			$partial = pop @lines;
		}

		foreach my $line (@lines) {
			$ircline_real++ unless $line =~ /^(?:8|PING)/;
			write_log('netdump', '', $line) if main::NETDUMP();
			print ">> $ircline_real $line\n" if DEBUG_ANY;
			foreach my $ev (parse_line($line)) {
				next unless $ev;

				callfuncs(@$ev);
			}
		}
	}
}

{
	my $watcher;

	sub ircd_connect($$) {
		my ($remote, $port) = @_;

		print "Connecting..." if DEBUG;
		$irc_sock = IO::Socket::INET->new(
			PeerAddr => $remote,
			PeerPort => $port,
			Proto => 'tcp',
			Blocking => 1,
		) or die("Could not connect to IRC server ($remote:$port): $!");
		$irc_sock->blocking(0);
		print " done\n" if DEBUG;

		$irc_sock->autoflush(1);

		$watcher = Event->io(
			cb => \&ircrecv,
			fd => $irc_sock,
			nice => -1,
		);
	}

	sub ircd_disconnect() {
		ircd_flush_queue();
		$watcher->cancel;
		$irc_sock->close;
	}
}

sub ircsendimm {
	print "ircsendimm()  ima_worker: ", ima_worker(), "\n" if DEBUG;

	if(defined $flood_queue) {
		print "FLOOD QUEUE ACTIVE\n" if DEBUG;
		push @$flood_queue, @_;
		return;
	}

	while(my $line = shift @_) {
		my $r;
		my $bytes = 0;
		my $len = length($line) + 2;
		write_log('netdump', '', split(NL, $line))
			if main::NETDUMP();
		while(1) {
			$r = $irc_sock->syswrite($line . NL, undef, $bytes);
			$bytes += $r if $r > 0;

			if($r <= 0 or $r < $len) {
				if($!{EAGAIN} or ($r > 0 and $r < $len)) {
					# Hold off to avoid flooding off
					print "FLOOD QUEUE ACTIVE\n" if DEBUG;

					$flood_queue = [];

					push @$flood_queue, substr($line, $bytes) unless $bytes == $len;
					push @$flood_queue, @_;

					Event->idle (
						min => 1,
						max => 10,
						repeat => 0,
						cb => \&flush_flood_queue
					);

					return;
				} else {
					irc_error($!);
					return;
				}
			}

			last if($bytes == $len);
		}
		print "<< $line\n" if DEBUG_ANY;
	}
}

sub ircsend {
	print "ircsend()  ima_worker: ", ima_worker(), "\n" if DEBUG;
	if(DEBUG) {
		foreach my $x (@_) {
			print "<< $ircline $x\n";
		}
	}

	if($ircd_ready) {
		ircsendimm(@_);
	} else {
		foreach my $x (@_) {
			if($x =~ /^@{[TOK_NICK]}/) {
				unshift @queue, $x;
			} else {
				push @queue, $x;
			}
		}
	}
}

sub ircd_flush_queue() {
	ircsendimm(@queue);
	undef @queue;
}

sub flush_flood_queue() {
	my $q = $flood_queue;
	undef $flood_queue;
	ircsendimm(@$q);
}

1;
