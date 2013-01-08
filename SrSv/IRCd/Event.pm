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

package SrSv::IRCd::Event;

use strict;

use Exporter 'import';
BEGIN { our @EXPORT_OK = qw(addhandler callfuncs) }

use SrSv::Debug;

use SrSv::Conf2Consts qw( main );

use SrSv::IRCd::Queue qw(ircd_enqueue);
use SrSv::IRCd::State qw($ircline $ircline_real synced initial_synced);

use SrSv::Message qw(add_callback message);

# FIXME
use constant {
	# Wait For
	WF_NONE => 0,
	WF_NICK => 1,
	WF_CHAN => 2,
	WF_ALL => 3,
};

sub addhandler($$$$;$) {
	my ($type, $src, $dst, $cb, $po) = @_;

	if($cb !~ /::/) {
		$cb = caller() . "::$cb";
	}

	print "Adding callback: $cb\n" if DEBUG;

	my @cond = ( CLASS => 'IRCD', TYPE => $type );
	push @cond, ( SRC => $src ) if($src);
	push @cond, ( DST => $dst ) if($dst);

	add_callback({
		NAME => $cb,
		TRIGGER_COND => { @cond },
		CALL => 'SrSv::IRCd::Event::_realcall',
		REALCALL => $cb,
		PARENTONLY => $po,
	});
}

our $last_highqueue = time();
sub callfuncs {
	my ($args, $sync, $wf, $message);

	if(@_ == 4) {
		$args = $_[3];
		$sync = 1;
		$wf = WF_NONE;
	} else {
		$args = $_[4];
		$sync = 0;
		$wf = $_[3];
	}
	$message = {
		CLASS => 'IRCD',
		TYPE => $_[0],
		SYNC => $sync,
		SRC => (defined($_[1]) ? $args->[$_[1]] : undef),
		DST => (defined($_[2]) ? $args->[$_[2]] : undef),
		WF => $wf,
		IRCLINE => ($sync ? $ircline : $ircline_real),
		ARGS => $args,
		ON_FINISH => ($sync ? undef : 'SrSv::IRCd::Queue::finished'), # FIXME
		SYNCED => [synced, initial_synced],
		QUEUE_DEPTH => SrSv::IRCd::Queue::queue_size(),
	};
	if(initial_synced && ($message->{QUEUE_DEPTH} > main_conf_highqueue) && ($last_highqueue < time()-5)) {
		ircd::privmsg(main_conf_local, main_conf_operchan, "HIGH TRAFFIC WARNING",
			"Queue depth exceeded @{[main_conf_highqueue]}") if defined(main_conf_operchan);
		ircd::privmsg(main_conf_local, main_conf_diag, "HIGH TRAFFIC WARNING",
			"Queue depth exceeded @{[main_conf_highqueue]}");
		$last_highqueue = time();
	}

	if($sync) {
		message($message);
	} else {
		ircd_enqueue($message);
	}
}

sub _realcall($$) {
	no strict 'refs';

	my ($message, $callback) = @_;

	print "Calling ", $callback->{REALCALL}, " ", join(',', @{$message->{ARGS}}), "\n" if DEBUG();
	local $ircline = $message->{IRCLINE};

	local $SrSv::IRCd::State::synced = $message->{SYNCED}[0]; # XXX This is questionable.
	local $SrSv::IRCd::State::initial_synced = $message->{SYNCED}[1];
	local $SrSv::IRCd::State::queue_depth = $message->{QUEUE_DEPTH};

	print "IRCLINE is $ircline  synced is $SrSv::IRCd::State::synced  initial_synced is $SrSv::IRCd::State::initial_synced\n" if DEBUG();

	&{$callback->{REALCALL}}(@{$message->{ARGS}});
	ircd::flushmodes() unless $message->{SYNC}; # FIXME
	print "Finished with $ircline\n" if DEBUG();
}

1;
