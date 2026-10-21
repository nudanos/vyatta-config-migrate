#!/usr/bin/perl
# Copyright (c) 2026, NuDanOS contributors.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# XorpConfigParser: a parsed config is written back out as recorded.

use strict;
use warnings;
use File::Temp qw(tempdir);
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

# parse $text and write it back out with output_to()
sub round_trip {
    my ($text) = @_;
    my $dir    = tempdir( CLEANUP => 1 );
    my $file   = "$dir/config.boot";
    open my $in, '>', $file or die "$file: $!\n";
    print {$in} $text;
    close $in or die "$file: $!\n";

    my $xcp = XorpConfigParser->new();
    local $SIG{ALRM} = sub { die "parse did not finish\n" };
    alarm 10;
    my $parsed = eval { $xcp->parse($file); 1 };
    alarm 0;
    return "error: $@" if !$parsed;

    my $got = q{};
    open my $fh, '>', \$got or die "$!\n";
    $xcp->output_to( $fh, 0 );
    close $fh or die "$!\n";
    return $got;
}

is(
    round_trip("system {\n    host-name r1\n}\n/* not closed"),
    "system {\n    host-name r1\n}\n/* not closed*/\n",
    'a comment left open at the end of the file'
);

is(
    round_trip("system {\n    host-name: r1\n    domain-name: \"example.com\"\n}\n"),
    "system {\n    host-name r1\n    domain-name \"example.com\"\n}\n",
    'unquoted and quoted "name: value" values'
);

done_testing();
