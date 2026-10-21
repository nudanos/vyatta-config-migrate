#!/usr/bin/perl

# Usage: vyatta_config_migrate.pl <config_file>
#
# Copyright (c) 2018-2019, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2014-2015 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use warnings;
use File::Copy  qw(copy);
use POSIX       qw(strftime);
use Sys::Syslog qw(:standard :macros);

# VYATTA_CONFIG_MIGRATE_DIR is for the tests
my $VYATTA_CONFIG_DIR   = $ENV{VYATTA_CONFIG_MIGRATE_DIR} // "/opt/vyatta/etc/config-migrate";
my $CURRENT_VERSION_DIR = "$VYATTA_CONFIG_DIR/current";
my $MIGRATE_DIR         = "$VYATTA_CONFIG_DIR/migrate";
my $CURRENT_CONF_VER    = '/opt/vyatta/sbin/vyatta_current_conf_ver.pl';

my $DEBUG_LOG = "/var/log/vyatta/migrate.log";
my $dbg       = 0;

sub debug {
    my ($msg) = @_;
    return if ( !$dbg );
    open( my $log, '>>', $DEBUG_LOG ) or return;
    print {$log} $msg;
    close $log;
    return;
}

# log a warning and give up
sub abort {
    my ( $debug_msg, $format, @args ) = @_;
    syslog( "warning", $format, @args );
    debug($debug_msg);
    exit 1;
}

debug("---\n");
openlog( "config-migrate", "", LOG_USER );

if ( @ARGV != 1 ) {
    print STDERR "Usage: vyatta_config_migrate.pl <config_file>\n";
    exit 1;
}
my $config_file = $ARGV[0];

# the config version of each "module" in the config file; undef if the
# file has no version string
sub config_versions {
    my ($file) = @_;
    my $conf;
    if ( !open( $conf, '<', $file ) ) {
        abort( "Cannot open config file $file. Migration aborted.\n",
            "Cannot open config file %s. Migration aborted", $file );
    }
    my @lines = <$conf>;
    close $conf;

    my $versions;
    foreach my $line (@lines) {
        chomp $line;
        next unless ( $line =~ m/===[ ]vyatta-config-version:[ ]"(.*?)"[ ]===/x );
        $versions = {};
        foreach my $modver ( split /:/x, $1 ) {
            my ( $mod, $ver ) = split /@/x, $modver;
            $versions->{$mod} = $ver;
        }
        last;
    }
    return $versions;
}

# the names in a directory, or an empty list (and false) if it cannot be read
sub dir_names {
    my ($dir) = @_;
    my $dh;
    return if ( ( !-d $dir ) || !opendir( $dh, $dir ) );
    my @names = readdir $dh;
    closedir $dh;
    return @names;
}

# the lines of a file
sub file_lines {
    my ($file) = @_;
    open( my $fh, '<', $file ) or return;
    local $/ = undef;
    my $contents = <$fh> // q{};
    close $fh;
    return split( /\n/x, $contents );
}

# a module the config names by an old name (listed in the current module's
# migrate/<module>/renamed-from) takes the current name
sub apply_renames {
    my ( $conf_version, $cur_version ) = @_;

    my %mod_renamed_from = ();
    foreach my $mod ( dir_names($MIGRATE_DIR) ) {
        if ( -e "$MIGRATE_DIR/$mod/renamed-from" ) {
            @{ $mod_renamed_from{$mod} } = file_lines("$MIGRATE_DIR/$mod/renamed-from");
        }
    }

    foreach my $cfg_mod_name ( keys %$conf_version ) {
        next if defined( $cur_version->{$cfg_mod_name} );
        foreach my $cur_mod_name ( sort keys %mod_renamed_from ) {
            next unless grep { $_ eq $cfg_mod_name } @{ $mod_renamed_from{$cur_mod_name} };

            # Found old module in config, replace it
            my $ver = delete $conf_version->{$cfg_mod_name};
            $conf_version->{$cur_mod_name} = $ver;
        }
    }
    return;
}

# copy the config to $backup_file before the first change
sub back_up {
    my ( $file, $backup_file ) = @_;

    # check if the config is writable. abort if not.
    if ( !-w $file ) {
        abort( "Config file $file is not writable. Migration aborted.\n",
            "Config file %s is not writable. Migration aborted.", $file );
    }
    if ( !copy( $file, $backup_file ) ) {
        abort(
            "Cannot back up the config file. Migration aborted.\n",
            "Cannot back up the config file. Migration aborted."
        );
    }
    return;
}

# run $mod's migration scripts from $conf_ver to $cur_ver, one version at
# a time; false if one fails
sub migrate_module {
    my ( $mod, $conf_ver, $cur_ver, $file ) = @_;

    while ( $conf_ver != $cur_ver ) {
        my $nxt_ver = ( $conf_ver < $cur_ver ) ? ( $conf_ver + 1 ) : ( $conf_ver - 1 );
        debug("$mod: $conf_ver -> $nxt_ver\n");
        my $cmd = "$MIGRATE_DIR/$mod/$conf_ver-to-$nxt_ver";
        my ( $ret, $err ) = ( 0, 'Migration script does not exist' );
        if ( -f $cmd ) {
            $ret = system( $cmd, $file );
            $err = $!;
        }
        else {
            # script does not exist. not an error (no-op).
            debug("Config file migration: module=$mod ver=$conf_ver nxt=$nxt_ver [$err]\n");
        }
        if ( $ret >> 8 ) {

            # script execution failed
            syslog( "warning", "Config file migration failed: module=%s ver=%s nxt=%s [%s]",
                $mod, $conf_ver, $nxt_ver, $err );
            debug("Config file migration failed: module=$mod ver=$conf_ver nxt=$nxt_ver [$err]\n");
            return 0;
        }
        $conf_ver = $nxt_ver;
    }
    return 1;
}

# the "/* Release version: ... */" line vyatta_current_conf_ver.pl prints
sub current_release_line {
    return if !-x $CURRENT_CONF_VER;
    open( my $out, '-|', $CURRENT_CONF_VER ) or return;
    my ($line) = grep { m{^/\*[ ]Release[ ]version:.*\*/$}x } <$out>;
    close $out;
    return $line;
}

# put $version_str in the config's version string, and the current release
# line in place of the old; false if the file cannot be written
sub rewrite_version {
    my ( $file, $version_str ) = @_;

    open( my $in, '<', $file ) or return 0;
    my @lines = <$in>;
    close $in;

    s/(===[ ]vyatta-config-version:[ ]").*("[ ]===)/$1$version_str$2/x foreach @lines;
    my $release = current_release_line();
    if ($release) {
        @lines = grep { !m{^/\*[ ]Release[ ]version:.*\*/$}x } @lines;

        # as "echo '$release' >>" wrote it before: its own newline and one more
        push @lines, "$release\n";
    }

    open( my $out, '>', $file ) or return 0;
    print {$out} @lines;
    return close $out;
}

my $conf_version = config_versions($config_file);
my $backup_file  = "$config_file." . strftime( '%F-%H%M', localtime ) . '.pre-migration';

# if the version string wasn't found, skip migration
if ( !defined($conf_version) ) {
    syslog( "info", "Version string not found. Skipping migration." );
    exit 0;
}

# the current config version of each "module"
sub current_versions {
    my @current = dir_names($CURRENT_VERSION_DIR);
    if ( !@current ) {
        syslog( "info", "No migration needed" );
        debug("Cannot open version directory $CURRENT_VERSION_DIR. No migration needed.\n");
        exit 0;
    }
    my %versions = ();
    foreach my $name (@current) {
        if ( $name =~ m/^([-\w]+)@(\d+)$/x ) {
            $versions{$1} = $2;
        }
    }
    return %versions;
}
my %cur_version = current_versions();

if ( !dir_names($MIGRATE_DIR) ) {
    debug("Cannot open migrate directory $MIGRATE_DIR. ");
    exit 0;
}
apply_renames( $conf_version, \%cur_version );

my $backup      = 1;
my $version_str = "";
my $status      = 0;

# check if each module needs migration
foreach my $mod ( sort( keys %cur_version ) ) {
    my $cur_ver  = $cur_version{$mod};
    my $conf_ver = $conf_version->{$mod} // 0;

    if ( $cur_ver == -1 ) {
        $cur_ver = 0;
    }

    if ( $conf_ver != $cur_ver ) {

        # migration needed
        if ($backup) {
            back_up( $config_file, $backup_file );
            $backup = 0;
        }
        $status = 1 if !migrate_module( $mod, $conf_ver, $cur_ver, $config_file );
    }
    if ( $version_str ne "" ) {
        $version_str .= ":";
    }
    $version_str .= "$mod\@$cur_ver";
}

# change the version string in the file if it's already changed
if ( !$backup && !rewrite_version( $config_file, $version_str ) ) {
    abort( "Cannot modify config file $config_file. Migration aborted.\n",
        "Cannot modify config file %s. Migration aborted.", $config_file );
}

if ( $status == 0 ) {
    if ($backup) {

        # config not changed
        syslog( "info", "No migration needed" );
    }
    else {
        syslog( "info", "Config file %s migrated.", $config_file );
    }
}

exit $status;
