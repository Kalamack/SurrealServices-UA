#!/usr/bin/perl

use strict;

use Event 'loop';
use IO::Handle;
use IO::Socket::INET;
use Errno ':POSIX';

sign_on_clients(200);

our @chans;
for(ord 'a' .. ord 'z') {
	push @chans, '#' . chr($_) x 3;
}

our @clients;

sub create_line_splitter($$) {
	my ($sock, $cb) = @_;
	my $part;

	return sub {
		my $event = shift;
		my ($r, $in);
		while($r = $sock->sysread($in, 4096) > 0) {
			my @lines = split(/\r?\n/s, $in, -1);
			
			$lines[0] = $part . $lines[0];
			$part = pop @lines;

			$cb->($_) foreach (@lines);
		}

		if($r <= 0 and not $!{EAGAIN}) {
			$event->w->cancel;
			$sock->close;
		}
	}
}

sub send_lines($@) {
	my $sock = shift;
	print "<< ", join("\n", @_), "\n";
	$sock->syswrite(join("\r\n", @_) . "\r\n");
}

sub junk($) {
	my $maxlen = shift;
	my $len = int(rand($maxlen/2) + $maxlen/2);

	my $out;
	while(--$len > 0) {
		$out .= chr(rand((ord 'z') - (ord 'a')) + ord 'a');
	}

	return $out;
}

sub irc_connect($) {
	my $sock = IO::Socket::INET->new (
		PeerAddr => $_[0],
		Type => SOCK_STREAM,
		Blocking => 0,
	);

	send_lines($sock,
		"NICK " . junk(9),
		"USER " . (junk(9) . ' ') x 3 . " :". junk(50),
	);

	push @clients, $sock;

	my $process_line = sub {
		my $line = shift;
		print ">> ", $line, "\n";

		if($line =~ /^PING :(.*)/) {
			send_lines($sock, "PONG :$1");
		}
		elsif($line =~ /\S+ 422/) {
			foreach (@chans) {
				send_lines($sock, "JOIN " . $_);
			}
		}
	};

	Event->io (
		fd => $sock,
		cb => create_line_splitter($sock, $process_line),
	);
}

sub sign_on_clients($) {
	my $num = shift;
	Event->timer (
		interval => 1,
		cb => sub {
			my $i = $num;
			return sub {
				$_[0]->w->cancel if(--$i < 0);
				irc_connect('localhost:6667');
			}
		}->(),
	);
}

our $stdin = new IO::Handle;
$stdin->fdopen(fileno(STDIN), "r");

Event->io (
	fd => $stdin,
	cb => create_line_splitter($stdin, sub {
		print eval $_[0], "\n";
		print $@ if $@;
	}),
);

loop();
