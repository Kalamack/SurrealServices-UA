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

package SrSv::Message;

use strict;

use Exporter 'import';
BEGIN { our @EXPORT_OK = qw(add_callback message call_callback unit_finished current_message) }

use Carp;
use Storable qw(fd_retrieve store_fd);

use SrSv::Debug;
BEGIN {
	if(DEBUG) {
		require Data::Dumper; import Data::Dumper ();
	}
}

use SrSv::Process::Call qw(safe_call);
use SrSv::Process::Worker qw(ima_worker get_socket multi call_in_parent call_all_child do_callback_in_child);

our %callbacks_by_trigger_class;
our %callbacks_by_after;
our %callbacks_by_name;

our $current_message;

### Public functions

sub add_callback($) {
	my ($callback) = @_;

	if(multi) {
		croak "Callbacks cannot be added at runtime";
	}

	if(my $after = $callback->{AFTER}) {
		push @{$callbacks_by_after{$after}}, $callback;
	}

	$callback->{NAME} = $callback->{CALL} unless $callback->{NAME};
	if(my $name = $callback->{NAME}) {
		push @{$callbacks_by_name{$name}}, $callback;
	}

	if(my $trigger = $callback->{TRIGGER_COND}{CLASS}) {
		push @{$callbacks_by_trigger_class{$trigger}}, $callback;
	}

	if(DEBUG()) {
		print "Added callback: $callback->{NAME}\n";
	}
}

sub message($) {
	my ($message) = @_;

	if(ima_worker()) {
		if($message->{SYNC}) {
			print "Triggered a sync callback!\n" if DEBUG();
			trigger_callbacks($message);
		} else {
			store_fd($message, get_socket());
			fd_retrieve(get_socket());
		}
		return;
	}

	trigger_callbacks($message);
}

### Semi-private ###

sub call_callback {
	my ($callback, $message) = @_;

	local $current_message = $message;

	if(my $call = $callback->{CALL}) {
		safe_call($call, [$message, $callback]);
	}
}

sub unit_finished($$) {
	my ($callback, $message) = @_;

	if(DEBUG()) {
		print "--- Finished unit\nCallback: $callback->{NAME}\nMessage: $message->{CLASS}\n";
	}

	safe_call($callback->{ON_FINISH}, [$callback, $message]) if $callback->{ON_FINISH};

	$message->{_CB_COUNTDOWN}--;
	print "_CB_COUNTDOWN is $message->{_CB_COUNTDOWN}\n---\n" if DEBUG;

	$message->{_CB_DONE}{$callback->{NAME}} = 1;

	if(!$message->{SYNC} and defined($message->{_CB_QUEUE}) and @{$message->{_CB_QUEUE}}) {
		trigger_callbacks($message);
	}

	if($message->{_CB_COUNTDOWN} == 0) {
		message_finished($message);
	}
}

sub message_finished($) {
	my ($message) = @_;

	print "Message finished: $message->{CLASS}\n" if DEBUG;

	for(qw(_CB_QUEUE _CB_COUNTDOWN _CB_DONE _CB_TODO)) {
		undef $message->{$_};
	}

	safe_call($message->{ON_FINISH}, [$message]) if $message->{ON_FINISH};
}

### Private functions ###

sub trigger_callbacks($) {
	my ($message) = @_;

	my $callbacks;

	if(defined($message->{_CB_QUEUE})) {
		$callbacks = $message->{_CB_QUEUE};
	} else {
		$callbacks = get_matching_callbacks($message);
	}

	if(@$callbacks) {
		$message->{_CB_COUNTDOWN} = @$callbacks unless defined($message->{_CB_COUNTDOWN});

		my $do_next = [];

		foreach my $callback (@$callbacks) {
			my $after = $callback->{AFTER};
			if($after and $message->{_CB_TODO}{$after} and not $message->{_CB_DONE}{$after}) {
				push @$do_next, $callback;
			} else {
				do_unit($callback, $message);
			}
		}

		$message->{_CB_QUEUE} = $do_next;

		goto &trigger_callbacks if($message->{SYNC} and @$do_next > 0);
	}

	else {
		if(DEBUG) {
			print "Message with no callbacks: ".Dumper($message);
		}

		message_finished($message);
	}
}

sub do_unit($$) {
	my ($callback, $message) = @_;

	if(!multi or $callback->{PARENTONLY} or $message->{SYNC}) {
		call_callback($callback, $message);
		unit_finished($callback, $message);
	} else {
		do_callback_in_child($callback, $message);
	}
}	

sub get_matching_callbacks($) {
	my ($message) = @_;
	my $ret = [];

	my $class = $message->{CLASS};

	foreach my $callback (@{$callbacks_by_trigger_class{$class}}) {
		if(callback_matches($message, $callback)) {
			push @$ret, $callback;
			$message->{_CB_TODO}{$callback->{NAME}} = 1;
		}
	}

	return $ret;
}

sub callback_matches($$) {
	my ($message, $callback) = @_;

	foreach my $cond (keys(%{$callback->{TRIGGER_COND}})) {
		if(ref($callback->{TRIGGER_COND}{$cond}) eq 'Regexp') {
			return 0 if defined($message->{$cond}) && !($message->{$cond} =~ $callback->{TRIGGER_COND}{$cond});
		} else {
			return 0 if defined($message->{$cond}) && !(lc $message->{$cond} eq lc $callback->{TRIGGER_COND}{$cond});
		}
	}

	return 1;
}

sub current_message() { return $current_message }

1;
