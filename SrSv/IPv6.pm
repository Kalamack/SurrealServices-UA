package SrSv::IPv6;

use Exporter qw( import );
use SrSv::Conf2Consts qw( main );

use SrSv::64bit;
BEGIN {
	our @EXPORT = qw( is_ipv6 get_ipv6_net get_ipv6_64 );
	if(main_conf_ipv6) {
		require Socket; import Socket;
		require Socket6; import Socket6;
		if(!HAS_64BIT_INT) {
			eval {
				require Math::BigInt;
				import Math::BigInt try => 'GMP';
			};
			if($@) {
				print STDERR "Running old version of perl/Math::BigInt.\n", $@, "Trying again.\n";
				require Math::BigInt;
				import Math::BigInt;
			}
		}
		push @EXPORT, qw( AF_INET6 );
	}
}

sub is_ipv6($) {
	my ($addr) = @_;
	if($addr =~ /^((?:\d{1,3}\.){3}\d{1,3})$/) {
		return 0 unless wantarray;
		return (0, $addr);
	}
	elsif($addr =~ /:ffff:((?:\d{1,3}\.){3}\d{1,3})$/) {
		return 0 unless wantarray;
		return (0, $1);
	} else {
		return 1 unless wantarray;
		return (1, $addr);
	}
}


sub get_ipv6_net($) {
# grabs the top 64bits of the IPv6 addr.
	my ($addr) = @_;
	my $str = Socket6::inet_pton(AF_INET6, $addr);
	my (@words) = unpack('H4H4H4H4H4H4H4H4', $str);
	my $int = ( !HAS_64BIT_INT ? Math::BigInt->bzero() : 0 );
	for(0..3) {
		$int <<= 16;
		$int |= hex($words[$_]);
	}
	return $int;
}

sub get_ipv6_64($) {
	my ($addr) = @_;
	my $str = Socket6::inet_pton(AF_INET6, $addr);
	return join(":", unpack("H4H4H4H4", $str))."::/64";
}

1;
