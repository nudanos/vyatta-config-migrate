# Copyright (c) 2026, NuDanOS contributors.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vyatta_config_migrate.pl: runs each module's migration scripts, up or
# down one version at a time, backs the config up first, and rewrites the
# version string.

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use Golden qw(data slurp is_golden);

my $root = "$FindBin::Bin/..";
my $dir  = tempdir( CLEANUP => 1 );
my $mig  = "$dir/config-migrate";

sub touch {
    my ($path) = @_;
    open my $fh, '>', $path or die "$path: $!\n";
    close $fh or die "$path: $!\n";
    return;
}

sub script {
    my ( $path, $body ) = @_;
    open my $fh, '>', $path or die "$path: $!\n";
    print {$fh} "#!/bin/sh\n$body\n";
    close $fh or die "$path: $!\n";
    chmod 0755, $path or die "$path: $!\n";
    return;
}

make_path( "$mig/current", map { "$mig/migrate/$_" } qw(broken config-management dhcp-server newmod webgui) );
touch("$mig/current/$_") for qw(broken@1 config-management@1 dhcp-server@5 newmod@2 webgui@0);

# each script notes that it ran in the config
my $note = 'echo "/* ran $(basename "$(dirname "$0")") $(basename "$0") */" >> "$1"';
script( "$mig/migrate/config-management/0-to-1", $note );
script( "$mig/migrate/dhcp-server/4-to-5",       $note );
script( "$mig/migrate/newmod/1-to-2",            $note );
script( "$mig/migrate/webgui/1-to-0",            $note );
script( "$mig/migrate/broken/0-to-1",            "$note\nexit 1" );
open my $fh, '>', "$mig/migrate/newmod/renamed-from" or die "$!\n";
print {$fh} "oldmod\n";
close $fh or die "$!\n";

my $config = "$dir/config.boot";
copy( data('driver.config'), $config ) or die "copy: $!\n";

local $ENV{VYATTA_CONFIG_MIGRATE_DIR} = $mig;
my $status = system( $^X, "$root/scripts/vyatta_config_migrate.pl", $config );
is( $status >> 8, 1, 'exits 1 when a migration script fails' );
is_golden( slurp($config), 'driver.migrated', 'scripts ran and the version string is current' );

my @backups = glob "$config.*.pre-migration";
is( scalar @backups, 1, 'one backup' );
is( slurp( $backups[0] ), slurp( data('driver.config') ), 'the backup is the original' );

copy( data('driver.migrated'), $config ) or die "copy: $!\n";
$status = system( $^X, "$root/scripts/vyatta_config_migrate.pl", $config );
is( $status >> 8, 0, 'exits 0 with nothing to migrate' );
is( slurp($config), slurp( data('driver.migrated') ), 'a current config is left alone' );

done_testing();
