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

package SrSv::Text::Format;

use strict;

use Encode 'encode';

use constant {
	MAX_WIDTH	=> 96,
	COLORS		=> 1,
	BULLET		=> encode('utf8', "\x{2022} "),
};

use Exporter 'import';
BEGIN { our @EXPORT_OK = qw( columnar enum wordwrap ) }

use SrSv::Text::Codes 'strip_codes';

BEGIN { if(COLORS) {
	*line_post = sub ($$) {
		my ($bg, $t) = @_;

		$t =~ s/^(.{60}.*?)\s*$/$1  / if length $t > 60;
		$t = "\0031,15" . $t if $bg;

		return split($/, $t);
	}
} else {
	*line_post = sub ($$) {
		my ($bg, $t) = @_;

		$t =~ s/ +$//;
		$t = ' ' unless $t;

		return split($/, $t);
	}
} }

sub columnar(@) {
	my $opts;
	$opts = shift if ref($_[0]) eq 'HASH';
	my (@mlen, @out);

	$opts->{DOUBLE} = 0 if $opts->{NOHIGHLIGHT};
	my $double = $opts->{DOUBLE};
	my $border = $opts->{BORDER};
	my $justified = $opts->{JUSTIFIED};

	foreach my $x (@_) {
		next unless ref($x) eq 'ARRAY';

		for(my $i; $i<@$x; $i++) {
			my $nc = strip_codes($x->[$i]);
			my $len = length($nc);
			$mlen[$i] = $len if $len > $mlen[$i];
		}
	}

	pop @mlen if $double;

	my $width = 2; # 2 leading spaces
	my $borderLine = '+';
	foreach my $x (@mlen) {
		my $cellWidth = ($x ? $x + 2 : 0);
		$width += $cellWidth;
		$borderLine .= '-'x($cellWidth+1).'+';
	}
	$border = $border && ($width < MAX_WIDTH);

	if($double and @mlen) {
		$mlen[-1] += MAX_WIDTH - $width;
		$width = MAX_WIDTH;
	}
	else {
		$width = MAX_WIDTH if $width > MAX_WIDTH;
	}

	my ($bg, $collapsed);
	my $headerBorder = 0;
	foreach my $x (@_) {
		if(ref $x eq 'HASH') {
			if(my $t = $x->{COLLAPSE}) {
				next unless @$t;
				if($border) {
					push @out, $borderLine;
				}
				push @out, ' ' unless $collapsed;
				@$t = map BULLET . $_, @$t if($x->{BULLET});
				push @out, @$t;
				$collapsed = 1;
			}
			else { $collapsed = 0 }

			if(my $t = $x->{FULLROW}) {
				my $nc = strip_codes($t);
				push @out, line_post $bg, '  ' . $t . ' ' x ($width - length($nc));
			}

			next;
		}

		my $str = ($border ? '| ' : '  ');
		#my $border = '+'.'-'x($width+1).'+';
		for(my $i; $i<@mlen; $i++) {
			my $nc = strip_codes($x->[$i]);
			if($justified && $i == 0) {
				$str .= ' ' x (($mlen[$i] - length($nc) + ($mlen[$i] ? 2 : 0))).
					$x->[$i] . ($border ? '| ' : '  ');
			} else {
				$str .= $x->[$i] .' ' x (($mlen[$i] - length($nc) + ($mlen[$i] ? 2 : 0))).
					($border ? '| ' : '  ');
			}
		}

		if($border) {
			if($headerBorder >= 2) {
			} else {
				push @out, $borderLine;
				$headerBorder++
			}
		}
		push @out, line_post $bg, $str;

		if($double and $x->[-1]) {
			my $t = $x->[-1];
			push @out, line_post $bg, "    $t" . ' ' x ($width - 4 - length strip_codes $t);
		}
	}
	continue {
		$bg = !$bg unless $opts->{NOHIGHLIGHT};
	}
	push @out, $borderLine if $border && !$collapsed && scalar(@_)!=1;

	push @out, '  (empty list)' unless @out;
	push @out, ' --';

	if(my $t = $opts->{TITLE}) {
		unshift @out, "\037$t" . (' ' x ($width - length strip_codes $t));
	}

	return @out;
}

# Formats a list like "foo, bar, and baz"
sub enum($@) {
	my ($conj, @list) = @_;

	my $el;
	$el = " $conj ".pop(@list) if(@list > 1);
	if(@list > 1) {
		$el = join(", ", @list) . ",$el";
	} else {
		$el = $list[0].$el;
	}

	return $el;
}

# Portions of wordwrap() taken from 
# Bjoern 'fuchs' Krombholz splitlong.pl
# bjkro@gmx.de
sub wordwrap ($$) {
	my ($data, $maxlength) = @_;

	return ($data)
		if (length($data) <= $maxlength);

	my $lstart = '...';
	my $lend = '...';
	my $maxlength2 = $maxlength - length($lend);

	my @spltarr;
	while (length($data) > ($maxlength2)) {
		my $pos = rindex($data, " ", $maxlength2);
		push @spltarr, substr($data, 0, ($pos < ($maxlength/10 + 4)) ? $maxlength2  : $pos)  . $lend;
		$data = $lstart . substr($data, ($pos < ($maxlength/10 + 4)) ? $maxlength2 : $pos + 1);
	}
	push @spltarr, $data;

	return @spltarr;
}

1;
