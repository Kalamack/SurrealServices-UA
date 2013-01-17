#!/usr/bin/perl
use strict;
use warnings;

use IO::Socket;
use Time::HiRes qw(gettimeofday);
my $socket = IO::Socket::INET->new(PeerAddr => '127.0.0.1',
		PeerPort => 7000,
		Proto    => "tcp")
		or die "Couldn't connect to localhost:7000 : $@\n";
$socket->autoflush(1);
&connected;
my @serverlist;
my %users;
while ( <$socket> ) { 
	print "-> $_";
	parsemsg($_); 
}

sub connected {
	# SERVER servername password hopcount id :description
	print $socket "SERVER services.test.net polarbears 0 00A :Services \n";
}
sub parsemsg {
	my $msg = $_;
	$msg =~ s/[\r\n]//g;
	if ($msg =~ /^SERVER (.*) (.*) (.*) (.*) :(.+)/) {
		push @serverlist, $4;
		ircsend(":00A BURST");
		ircsend(":services.test.net VERSION :SurrealServices 00A");
		ircsend(":00A UID 00AAAAAAB ".time." NickServ services.test.net services.test.net NickServ 0.0.0.0 ".time." +io :Nickname Services");
		ircsend(":00AAAAAAB OPERTYPE Services");
                ircsend(":00A UID 00AAAAAAC ".time." ChanServ services.test.net services.test.net ChanServ 0.0.0.0 ".time." +io :Channel Services");
                ircsend(":00AAAAAAC OPERTYPE Services");
                ircsend(":00A UID 00AAAAAAD ".time." MemoServ services.test.net services.test.net MemoServ 0.0.0.0 ".time." +io :Memo Services");
                ircsend(":00AAAAAAD OPERTYPE Services");
                ircsend(":00A UID 00AAAAAAE ".time." OperServ services.test.net services.test.net OperServ 0.0.0.0 ".time." +io :Oper Services");
                ircsend(":00AAAAAAE OPERTYPE Services");
		ircsend(":00A ENDBURST");
		ircsend(":00A PING 00A $serverlist[0]");
	}
	if ($msg =~ /^:(.*) PING (.*) (.*)$/) {
		if ($1 eq $serverlist[0]) {
			ircsend(":00A PONG 00A $serverlist[0]");
		}
	}
	if ($msg =~ /^:(.*) FJOIN (.*) (.*) (.+) :?(.+)$/) {
		parse_fjoin($1,$2,$3,$4,$5);
	}
	if ($msg =~ /^:(.*) IDLE (.*)$/) {
		parse_idle($1,$2);
	}
	if ($msg =~ /^:(.*) UID (\S+) (\d+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (.+) :(.+)$/) {
		parse_uid($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11);
	}
	if ($msg =~ /^:(.*) PRIVMSG (\S+) :(.+)$/) {
		parse_privmsg($1,$2,$3);
	}
}
sub ircsend {
	my $msg = shift;
	print "<- $msg\n";
	$msg .= " \n";
	print $socket $msg;
}

sub parse_fjoin {
	#:431 FJOIN #test 1246571540 +nt :,431AAAAAC ,431AAAAAA
	my ($src, $chan, $ts, $modes, $users) = @_;
	if ($chan eq "#test") {
		print "!!! aa - $modes\n";
		ircsend(":00A FJOIN $chan $ts $modes :o,00AAAAAAB o,00AAAAAAC o,00AAAAAAD o,00AAAAAAE");
	}
}
sub parse_idle {
	my ($src, $target) = @_;
	ircsend(":$target IDLE $users{$src}{'nick'} ".time." 0");
}
sub parse_uid {
	#:431 UID 431AAAAAA 1246349244 MusashiX90 127.0.0.1 netadmin.omega.org.za nano 127.0.0.1 1246349249 +Wios +ACJKLNOQacdfgjklnoqtx :mwt
	my ($src, $uid, $ts, $nick, $hostname, $cloak, $ident, $ip, $signon, $modes, $realname) = @_;
	print "DEBUG: Added '$nick' to users\n";
	$users{$uid}{'nick'} = $nick;
}

sub parse_privmsg {
	my ($src, $target, $msg) = @_;
	# PRIVMSG sent to MemoServ
	if ($target eq "00AAAAAAD") {
		ircsend(":$target NOTICE $src :Received your message");
	}
}
