#!/usr/bin/perl
# Copyright (c) 2019, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2014-2015 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use warnings;

my $VYATTA_CONFIG_DIR   = "/opt/vyatta/etc/config-migrate";
my $CURRENT_VERSION_DIR = "$VYATTA_CONFIG_DIR/current";

# get the current config version of each "module"
my $cur;
if ( ( !-d $CURRENT_VERSION_DIR ) || !opendir( $cur, "$CURRENT_VERSION_DIR" ) ) {
    print "\n";
    exit 0;
}
my $version_str = "";
foreach ( readdir $cur ) {
    if (m/^([-\w]+)@(\d+)$/x) {
        if ( $version_str ne "" ) {
            $version_str .= ":";
        }
        $version_str .= ( "$1" . "@" . "$2" );
    }
}
closedir $cur;

print "\n\n/* Warning: Do not remove the following line. */\n";
print "/* === vyatta-config-version: \"$version_str\" === */\n";

# output "release" version. note that this may be unreliable after package
# upgrades or downgrades.
if ( open( my $ver_fh, '<', "/opt/vyatta/etc/version" ) ) {
    my $line = <$ver_fh> // q{};
    if ( $line =~ /^Version\s*:\s*(\S.*)$/x ) {
        my $ver = $1;
        print "/* Release version: $ver */\n";
    }
    close $ver_fh;
}

exit 0;
