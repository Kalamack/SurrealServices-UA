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

package SrSv::IRCd::Queue;

# The purpose of this module is to make sure lines get processed in an
# order that makes sense, e.g., a JOIN should not be processed before
# the corresponding NICKCONN has been.

# FIXME: This may not be well optimized. It also can be fouled up by
# conflicting messages with the same WF value, such as the same nick
# disconnecting and connecting at once.

use strict;

use Exporter 'import';
BEGIN { our @EXPORT_OK = qw(ircd_enqueue queue_size) }

use SrSv::Debug;
use SrSv::Message qw(message);

our @queue = map [], 0..3; # 3 is the maximum WF value

sub ircd_enqueue($) {
	my ($message) = @_;
	my ($ircline, $wf) = @$message{'IRCLINE', 'WF'};

	if($wf == 0) {
		message($message);
		return;
	}

	push @{$queue[$wf]}, $message;
	
	if(_is_runnable($message)) {
		print "$message->{IRCLINE} is runnable immediately. (WF=$message->{WF})\n" if DEBUG;
		message($message);
		$message->{_Q_RUNNING} = 1;
	}
}

sub queue_size() {
	my $r;
	foreach (@queue) { $r += @$_ }
	return $r;
}

sub finished {
	my ($message) = @_;
	my ($ircline, $wf) = @$message{'IRCLINE', 'WF'};

	print "Called finished() for $ircline\n" if DEBUG();

	for(my $i; $i < @{$queue[$wf]}; $i++) {
		if($queue[$wf][$i]{IRCLINE} == $ircline) {
			splice(@{$queue[$wf]}, $i, 1);
			last;
		}
	}

	if($message->{TYPE} eq 'SEOS') {
		$message->{TYPE} = 'POSTSEOS';
		message($message);
	}

	_dequeue();
}

sub _is_runnable($) {
	my ($message) = @_;
	my ($ircline, $wf) = @$message{'IRCLINE', 'WF'};
	
	for(1..($wf-1)) {
		if(defined($queue[$_][0]) and $queue[$_][0]{IRCLINE} < $ircline) {
			print "Line $ircline must wait for $queue[$_][0]{IRCLINE}\n" if DEBUG;
			return 0;
		}
	}

	return 1;
}

sub _dequeue {
	foreach my $q (@queue) {
		INNER: foreach my $message (@$q) {
			next INNER if $message->{_Q_RUNNING};
			
			if(_is_runnable($message)) {	
				print "$message->{IRCLINE} is now runnable\n" if DEBUG;

				message($message);
				$message->{_Q_RUNNING} = 1;
			}
			else {
				last INNER;
			}
		}
	}
}

1;
