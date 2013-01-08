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
package modes;

use strict;
no strict 'refs';
use constant {
	DEBUG => 0,

	DIFF => 1,
	ADD => 2,
	MERGE => 3
};

# This gives what we need to do to bring a current modeset into compliance
# with a specified modeset (used for modelock)
sub diff($$$) {
	return calc($_[0], $_[1], $_[2], DIFF);
}

# This gives the result of applying the mode changes in the second parameter
# to the existing modes in the first parameter.
sub add($$$) {
	return calc($_[0], $_[1], $_[2], ADD);
}

# This gives back the modes in the first parameter, with any modes in the
# second overriding the first. (used to validate modelock setting)
sub merge($$$) {
	return calc($_[0], $_[1], $_[2], MERGE);
}

sub invert($) {
	my @modes = split(/ /, $_[0]);

	$modes[0] =~ tr/+-/-+/;

	return join(' ', @modes);
}

# This removes the channel key, for info displays
sub sanitize($) {
	my ($modes, @parms) = split(/ /, $_[0]);
	my @modes = split(//, $modes);
	my ($c, $sign);

	foreach my $m (@modes) {
		if($m eq '+') { $sign = 1; next; }
		if($m eq '-') { $sign = 0; next; }
		
		if($sign) {
			if($m =~ $ircd::ocm) {
				$parms[$c] = '*' if $m eq 'k';
				$c++;
			}
		}
	}

	return join(' ', $modes, @parms);
}

sub get_key($) {
	my ($modes, @parms) = split(/ /, $_[0]);
	my @modes = split(//, $modes);
	my ($c, $sign);

	foreach my $m (@modes) {
		if($m eq '+') { $sign = 1; next; }
		if($m eq '-') { $sign = 0; next; }
		
		if($sign) {
			if($m =~ $ircd::ocm) {
				return $parms[$c] if ($m eq 'k');
				$c++;
			}
		}
	}

	return undef;
}

#  This is far from the best way to do it.
#  
#  'bekfLlvhoaq' 'kfLlj'
######
# This really needs to be made more generic
# learn more about $ircd::ocm $ircd::scm $ircd::acm
######
sub calc($$$$) {
	my ($src, $dst, $chan, $type) = @_;

	my ($smodes, @sargs) = split(/ /, $src);
	my ($dmodes, @dargs) = split(/ /, $dst);

	#$smodes =~ s/[bevhoaq]//g if $chan;
	
	my @smodes = split(//, $smodes);
	my @dmodes = split(//, $dmodes);
	
	my $sign = 2;
	my (@tmodes, @targs, @omodes, @oargs, $rmodes, @rargs, %status);
	
	foreach my $x (@smodes) {
		if($x eq '+') { $sign=2; next; }
		if($x eq '-') { $sign=1; next; }
		if($chan and $x =~ $ircd::scm) {
			#shift @sargs if($sign == 2);
			my $t = shift @sargs;
			if($type == MERGE) {
				my $key;
				if($x =~ /^[beIk]$/) {
					$key = $t;
				} else {
					$key = lc $t;
				}
				$status{$x}{$key} = $sign;
			}
			next;
		}
		if($chan and $x !~ $ircd::acm) {
			next;
		}
	
		if($type == DIFF or $type == ADD) {
			$tmodes[ord($x)] = $sign if $type == DIFF;
			$omodes[ord($x)] = $sign if $type == ADD;
			
			if($chan and $sign == 2 and $x =~ $ircd::ocm) {
				$targs[ord($x)] = shift @sargs if $type == DIFF;
				$oargs[ord($x)] = shift @sargs if $type == ADD;
			}
		}
		
		elsif($type == MERGE) {
			if($chan and $sign == 2 and $x =~ $ircd::ocm) {
				if(
					($x eq 'l' and $sargs[0] =~ /^\d+$/) or
					($x eq 'L' and $sargs[0] =~ /^#/) or
					$x eq 'f' or $x eq 'k' or 
					($x eq 'j' and $sargs[0] =~ /^\d+\:\d+$/)
				) {
					$omodes[ord($x)] = $sign;
					$oargs[ord($x)] = shift @sargs;
				}
			} else {
				$omodes[ord($x)] = $sign;
			}
		}
	}

	foreach my $x (@dmodes) {
		if($x eq '+') { $sign=2; next; }
		if($x eq '-') { $sign=1; next; }
		if($chan and $x =~ $ircd::scm) {
			#shift @dargs if($sign == 2);
			my $t = shift @dargs;
			if($type == MERGE) {
				my $key;
				if($x =~ /^[beIk]$/) {
					$key = $t;
				} else {
					$key = lc $t;
				}
				$status{$x}{$key} = $sign;
			}
			next;
		}
		if($chan and $x !~ $ircd::acm) {
			next;
		}

		if($chan and $sign == 2 and $x =~ $ircd::ocm) {
			$oargs[ord($x)] = shift @dargs;
		}

		if(
			$type == ADD or
			$type == MERGE or
			$type == DIFF and (
				($sign==2 or $tmodes[ord($x)]) and (
					$sign != $tmodes[ord($x)] or
					$targs[ord($x)] ne $oargs[ord($x)]
				)
			)
		) {
			$omodes[ord($x)] = $sign;
		}

		# -k won't work without its parameter!
		if($chan and $type == DIFF and $sign == 1 and $x eq 'k') {
			$oargs[ord($x)] = $targs[ord($x)];
		}
	}

	$sign = 0;
	for(my $i = 0; $i < scalar @omodes; $i++) {
		if($omodes[$i] == 2) {
			if($sign != 2) { $sign = 2; $rmodes .= '+'; }
			$rmodes .= chr($i);
			push @rargs, $oargs[$i] if $oargs[$i];
			
		}
	}

	if($type == MERGE) {
		foreach my $m (keys(%status)) {
			foreach my $v (keys(%{$status{$m}})) {
				if($status{$m}{$v} == 2) {
					if($sign != 2) { $sign = 2; $rmodes .= '+'; }
					$rmodes .= $m;
					push @rargs, $v;
				}
			}
		}
	}
	
	if($type == DIFF or $type == MERGE) {
		for(my $i = 0; $i < scalar @omodes; $i++) {
			if($omodes[$i] == 1) {
				if($sign != 1) { $sign = 1; $rmodes .= '-'; }
				$rmodes .= chr($i);
				push @rargs, $oargs[$i] if $oargs[$i];
			}
		}
	}

	if($type == MERGE) {
		foreach my $m (keys(%status)) {
			foreach my $v (keys(%{$status{$m}})) {
				if($status{$m}{$v} == 1) {
					if($sign != 1) { $sign = 1; $rmodes .= '-'; }
					$rmodes .= $m;
					push @rargs, $v;
				}
			}
		}
	}
	
	#return undef if($rmodes eq '+');
	print "modes::calc($src, $dst, $chan, $type)\n" if DEBUG();
	print "--- MODE CALCULATED: ", join(' ', $rmodes, @rargs), "\n" if DEBUG();
	return join(' ', $rmodes, @rargs);
}

# Splits modes into a hash
# Skips modes in $ircd::scm (opmodes and banmodes)
sub splitmodes($) {
	my ($modes) = @_;
	my (%modelist, @parms);
	($modes, @parms) = split(/ /, $modes);
	my $sign = '+';
	foreach my $mode (split(//, $modes)) {
		if ($mode eq '+' or $mode eq '-') {
			$sign = $mode;
		}
		elsif($mode =~ $ircd::scm) {
			shift @parms;
		}
		elsif($mode =~ $ircd::ocm) {
			push @{$modelist{$mode}}, $sign, shift @parms;
		}
		elsif($mode =~ $ircd::acm) {
			push @{$modelist{$mode}}, $sign;
		}
	}
	return %modelist;
}

sub splitumodes($) {
	my ($modes) = @_;
	my %modelist;
	my $sign = '+';
	foreach my $mode (split(//, $modes)) {
		if ($mode eq '+' or $mode eq '-') {
			$sign = $mode;
		}
		else {
			$modelist{$mode} = $sign;
		}
	}
	return %modelist;
}

# umodes that should not be settable by services
# Most are OperModes [thus most are legal to be set for /os oper]
our %unsafeumodes = (
	o => 1, # Global Oper
	O => 1, # Local Oper [wouldn't ever show up to remote servers]
	A => 1, # Server Admin
	C => 1, # Server CoAdmin (little diff in ability vs Admin)
	a => 1, # Services Admin
	N => 1, # Network Admin
	W => 1, # See WHOIS events
	g => 1, # see GLOBOPS
	s => 1, # SNOMASKs. variable. has parameters, only settable via svssno
	S => 1, # For Network Service Agents only. Protects from various
	h => 1, # Can see /helpop msgs /.\ good for a helpop/helper
	v => 1, # can see rejected/blocked DCC messages /.\ good for a helpop/helper
	q => 1, # Can wok through walls. Kidding, avoid/block non-server/services kicks

	z => 1, # Strictly speaking not unsafe, but shouldn't be allowed
	t => 1, # Not unsafe either, but pointless as it won't have the desired effect
	x => 1, # Ditto
	r => 1  # This should be taken care of by identifying, if you're on a reg'd nick.
);

sub allowed_umodes($) {
	my ($modes) = @_;
	my %modelist = splitumodes($modes);
	my ($rejected, $rejectedSign);
	foreach my $mode (keys(%modelist)) {
		if(defined ($unsafeumodes{$mode})) {
			if(defined($rejectedSign) && $rejectedSign eq $modelist{$mode}) {
			} else {
				$rejectedSign = $modelist{$mode};
				$rejected .= $rejectedSign;
			}
			$modelist{$mode} = undef;
			$rejected .= $mode;
		}
	}
	return (unsplit_umodes(%modelist), $rejected);
}

# split + unsplit equals a modes::merge for umodes
sub unsplit_umodes(%) {
	my (%modelist) = @_;
	my ($upmodes, $downmodes) = ('', '');
	foreach my $mode (keys(%modelist)) {
		if ($modelist{$mode} eq '+') {
			$upmodes .= $mode;
		}
		elsif ($modelist{$mode} eq '-') {
			$downmodes .= $mode;
		}
	}
	return ($upmodes ne '' ? "+$upmodes" : '').($downmodes ne '' ? "-$downmodes" : '');
}

sub merge_umodes($;$) {
# second param is optional as we may want to merge a string of mixed modes '+rh-x+i'
	my ($umodes1, $umodes2) = @_;
	return modes::unsplit_umodes(modes::splitumodes($umodes1 . ($umodes2 ? $umodes2 : '' ) ) );
}

1;
