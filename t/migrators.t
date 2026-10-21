# Copyright (c) 2026, NuDanOS contributors.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# The migration scripts turn the fixtures into the recorded configs.

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../scripts", "$FindBin::Bin/../lib";
use Test::More;
use Golden qw(is_golden run_migrator);

my $root = "$FindBin::Bin/..";

for my $step (qw(3-to-2 3-to-4 4-to-3 4-to-5 5-to-4)) {
    my ( $got, $status ) =
      run_migrator( 'dhcp.config', $^X, "$root/migrate/dhcp-server/$step" );
    is( $status, 0, "dhcp-server $step exits 0" );
    is_golden( $got, "dhcp.dhcp-server-$step", "dhcp-server $step" );
}

{
    my ( $got, $status ) = run_migrator( 'dhcp.config', $^X,
        "$root/migrate/config-management/0-to-1" );
    is( $status, 0, 'config-management 0-to-1 exits 0' );
    is_golden( $got, 'dhcp.config-management-0-to-1',
        'config-management 0-to-1' );
}

for my $action (
    qw(dhcp_relay_0_to_1 dhcp_relay_1_to_0 dhcp_server_0_to_1
    dhcp_server_1_to_0 dhcp_server_1_to_2 dhcp_server_2_to_1
    webgui_0_to_1 webgui_1_to_0)
  )
{
    my ( $got, $status ) = run_migrator(
        'xorp.config', $^X, "$root/scripts/XorpConfigMigrator.pl",
        '--input=FILE', '--output=FILE', "--action=migrate_service_$action"
    );
    is( $status, 0, "XorpConfigMigrator $action exits 0" );
    is_golden( $got, "xorp.$action", "XorpConfigMigrator $action" );
}

{
    my $script = <<'END';
use Vyatta::Config::Migrate qw(migrate);
migrate( $ARGV[0], sub { $_[0]->set_value( [ 'system', 'domain-name' ], 'example.net' ) } );
END
    my ( $got, $status ) = run_migrator( 'dhcp.config', $^X, '-e', $script );
    is( $status, 0, 'Vyatta::Config::Migrate::migrate exits 0' );
    is_golden( $got, 'dhcp.migrate-pm', 'Vyatta::Config::Migrate::migrate' );
}

done_testing();
