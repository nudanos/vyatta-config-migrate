#!/usr/bin/perl
# Copyright (c) 2026, NuDanOS contributors.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# XorpConfigParser: a parsed config is written back out as recorded.

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../scripts";
use Test::More;
use Golden qw(data is_golden);
use XorpConfigParser;

for my $name (qw(dhcp xorp)) {
    my $xcp = XorpConfigParser->new();
    $xcp->parse( data("$name.config") );
    my $got = q{};
    open my $fh, '>', \$got or die "$!\n";

    # output() writes to the selected handle; callers in other packages
    # select a file first
    my $old = select $fh;    ## no critic (InputOutput::ProhibitOneArgSelect) reason: the interface under test
    $xcp->output(0);
    select $old;             ## no critic (InputOutput::ProhibitOneArgSelect) reason: the interface under test
    close $fh or die "$!\n";
    is_golden( $got, "$name.parsed", "$name.config round trip" );
}

done_testing();
