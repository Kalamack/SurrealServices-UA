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
package module;
use strict;
no strict 'refs';

use Symbol qw(delete_package);

use SrSv::Conf2Consts qw(main);

use constant {
	ST_UNLOADED => 0,
	ST_LOADED => 1,
	ST_READY => 2,
};

our %modules;
our %packages;
our @modules;

our @unload;
our @load;

sub load(@) {
	my @m = @_;
	@m = @modules = split(/\s*,\s*/, main_conf_load) unless @m;

	foreach my $module (@m) {
		next if ($modules{$module} and $modules{$module}[0] and !($modules{$module}[0] == ST_UNLOADED));
		
		my $m = "./modules/$module.pm";
		print "Loading module $module..."; # if $main::status==main::ST_PRECONNECT();
		eval { require $m };
		if($@) {
			#if($main::status==main::ST_PRECONNECT()) {
				print qq{ FAILED.\n\nModule "$module" failed to load.\n};

				my $error = $@;
				$error =~ s/\n(?:BEGIN failed--|Compilation failed in require).*(?:\n|$)//sg unless main::DEBUG();
				print "Please read INSTALL and README.\nOr if you just upgraded, see UPGRADING.\n" unless main::DEBUG();
				print "\n$error\n";
				exit;
			#} else {
			#	return $@;
			#}
		}
		
		foreach my $p (@{"$module\::packages"}) {
			$packages{$p}{$module} = 1;
		}
		
		print " done.\n"; #if $main::status==main::ST_PRECONNECT();

		$modules{$module}[0] = ST_LOADED;
	}

	foreach my $module (@m) {
		my $m = "$module\::init";
		eval { &$m(); };

		if($@) {
			print qq{ FAILED.\n\nModule "$module" failed to load.\n};
			print "\n$@\n";
			exit;
		}
	}

	return undef;
}

sub unload(@) {
	my @m = @_;
	@m = @modules unless @m;
	
	unload_lazy(@m);

	foreach my $module (@m) {
		next unless $modules{$module}[0] == ST_UNLOADED;
		
		delete_package $module;

		foreach my $p (keys(%packages)) {
			delete $packages{$p}{$module};

			unless(keys(%{$packages{$p}})) {
				delete_package $p;
			}
		}
	}
}

sub unload_lazy(@) {
	my @m = @_;
	@m = @modules unless @m;
	
	foreach my $module (@m) {
		next unless $modules{$module}[0] == ST_LOADED;
		
		my $m = "$module\::unload";
		eval { &$m };
		print $@ if $@;

		$modules{$module}[0] = ST_UNLOADED;
	}
}

sub begin(@) {
	my @m = @_;
	@m = @modules unless @m;
	
	foreach my $module (@m) {
		next unless $modules{$module}[0] == ST_LOADED;
		
		my $m = "$module\::begin";
		eval { &$m };
		print $@ if $@;

		$modules{$module}[0] = ST_READY;
	}
}

sub end(@) {
	my @m = @_;
	@m = @modules unless @m;
	
	foreach my $module (@m) {
		next unless $modules{$module}[0] == ST_READY;
		
		my $m = "$module\::end";
		eval { &$m };
		print $@ if $@;

		$modules{$module}[0] = ST_LOADED;
	}
}

sub is_loaded(@) {
	foreach my $module (@_) {
		return 0 if($modules{$module}[0] == ST_UNLOADED);
	}

	return 1;
}

1;
