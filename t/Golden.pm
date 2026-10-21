# Copyright (c) 2026, NuDanOS contributors.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# Test helper: compare output with a file in t/data, or write that file
# when UPDATE_GOLDEN is set (to record the behaviour of the code as it is).

package Golden;

use strict;
use warnings;
use parent     qw(Exporter);
use File::Copy qw(copy);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

our @EXPORT_OK = qw(data slurp is_golden run_migrator);

my $root = "$FindBin::Bin/..";

sub data { my ($name) = @_; return "$FindBin::Bin/data/$name"; }

sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or return;
    local $/ = undef;
    my $s = <$fh>;
    close $fh or return;
    return $s;
}

sub is_golden {
    my ( $got, $name, $what ) = @_;
    my $path = data($name);
    if ( $ENV{UPDATE_GOLDEN} ) {
        open my $fh, '>', $path or die "$path: $!\n";
        print {$fh} $got;
        close $fh or die "$path: $!\n";
    }
    my $want = slurp($path);
    return is( $got, $want, $what );
}

# Run a command on a copy of t/data/$input as its last argument (or, when
# an argument is the string FILE, in its place); returns the copy's
# contents afterwards and the command's exit status.
sub run_migrator {
    my ( $input, @cmd ) = @_;
    my $dir  = tempdir( CLEANUP => 1 );
    my $file = "$dir/config.boot";
    copy( data($input), $file ) or die "copy: $!\n";
    my @args = map { s/FILE/$file/xr } @cmd;
    push @args, $file unless grep { /FILE/x } @cmd;
    local $ENV{PERL5LIB} = join ':', "$root/scripts", "$root/lib", ( $ENV{PERL5LIB} // () );
    my $status = system { $args[0] } @args;
    return ( slurp($file), $status );
}

1;
