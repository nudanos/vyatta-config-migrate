#!/usr/bin/perl
# Copyright (c) 2019, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2014-2015 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use warnings;
use lib "/opt/vyatta/share/perl5/";
use NetAddr::IP;    # This library is available via libnetaddr-ip-perl.deb
use XorpConfigParser;

use Getopt::Long;
my $input;
my $output;
my $action;
GetOptions( "input=s" => \$input, "output=s" => \$output, "action=s" => \$action );

my $xcp = XorpConfigParser->new();

my %actions = (
    migrate_service_dhcp_relay_0_to_1  => \&migrate_service_dhcp_relay_0_to_1,
    migrate_service_dhcp_relay_1_to_0  => \&migrate_service_dhcp_relay_1_to_0,
    migrate_service_dhcp_server_0_to_1 => \&migrate_service_dhcp_server_0_to_1,
    migrate_service_dhcp_server_1_to_0 => \&migrate_service_dhcp_server_1_to_0,
    migrate_service_dhcp_server_1_to_2 => \&migrate_service_dhcp_server_1_to_2,
    migrate_service_dhcp_server_2_to_1 => \&migrate_service_dhcp_server_2_to_1,
    migrate_service_webgui_0_to_1      => \&migrate_service_webgui_0_to_1,
    migrate_service_webgui_1_to_0      => \&migrate_service_webgui_1_to_0,
);

# an unknown action is an error before the output is touched: written
# out, the empty tree would replace the config
my $migrate = $actions{ $action // q{} };
die "Unknown action \"" . ( $action // q{} ) . "\"\n" if !$migrate;
$migrate->($input);

if ( defined($output) && $output ne q{} ) {
    $xcp->write_file($output) or die "Cannot write $output: $!\n";
}
else {
    $xcp->output_to( \*STDOUT, 0 );
}

# the DHCP options that dhcp-server 0 and 1 have in common
my @dhcp_server_options = (
    'start',          'exclude',     'static-mapping', 'dns-server',
    'default-router', 'wins-server', 'lease',          'domain-name',
    'authoritative'
);

sub copy_dhcp_server_options {
    my ( $from, $to ) = @_;
    foreach my $option (@dhcp_server_options) {
        $xcp->copy_node( $from, $to, $option );
    }
    return;
}

sub migrate_service_dhcp_relay_0_to_1 {
    my ($file) = @_;
    $xcp->parse($file);

    my $hashService         = $xcp->get_node( ['service'] );
    my $hashServiceChildren = $hashService->{'children'};

    my $hashServiceDhcpRelay = $xcp->get_node( [ 'service', 'dhcp', 'relay' ] );
    if ( defined($hashServiceDhcpRelay) ) {
        my $childrenServiceDhcpRelay = $hashServiceDhcpRelay->{'children'};
        my @multis                   = $xcp->copy_multis( $childrenServiceDhcpRelay, 'interface' );
        foreach my $multiServiceDhcpRelayInterface (@multis) {
            my $childrenInterface = $multiServiceDhcpRelayInterface->{'children'};

            my @childrenDhcpRelay;
            my %hashDhcpRelay = (
                'name'     => 'dhcp-relay',
                'children' => \@childrenDhcpRelay
            );
            my %hashDhcpRelayInterface =
              ( 'name' => 'interface ' . $multiServiceDhcpRelayInterface->{'name'} );
            push( @childrenDhcpRelay, \%hashDhcpRelayInterface );

            $xcp->copy_node( $childrenInterface, \@childrenDhcpRelay, 'server' );
            $xcp->copy_node( $childrenInterface, \@childrenDhcpRelay, 'relay-options' );

            push( @$hashServiceChildren, \%hashDhcpRelay );
        }
    }

    $xcp->comment_out_child( $hashServiceChildren, 'dhcp' );
    return;
}

sub migrate_service_dhcp_relay_1_to_0 {
    my ($file) = @_;
    $xcp->parse($file);

    my $hashService         = $xcp->get_node( ['service'] );
    my $hashServiceChildren = $hashService->{'children'};

    my @pathServiceDhcp_Relay = ( 'service', 'dhcp', 'relay' );
    $xcp->set_value( \@pathServiceDhcp_Relay, q{} );
    my $hashServiceDhcp_Relay     = $xcp->get_node( [ 'service', 'dhcp', 'relay' ] );
    my $childrenServiceDhcp_Relay = $hashServiceDhcp_Relay->{'children'};
    if ( !defined($childrenServiceDhcp_Relay) ) {
        my @childrenServiceDhcp_Relay;
        $hashServiceDhcp_Relay->{'children'} = \@childrenServiceDhcp_Relay;
        $childrenServiceDhcp_Relay = \@childrenServiceDhcp_Relay;
    }

    my $hashServiceDhcpRelay = $xcp->get_node( [ 'service', 'dhcp-relay' ] );
    if ( defined($hashServiceDhcpRelay) ) {
        my $childrenServiceDhcpRelay = $hashServiceDhcpRelay->{'children'};
        my @multis                   = $xcp->copy_multis( $childrenServiceDhcpRelay, 'interface' );
        foreach my $multiServiceDhcpRelayInterface (@multis) {
            my @childrenDhcpRelayInterface;
            my %hashDhcpRelayInterface = (
                'name'     => 'interface ' . $multiServiceDhcpRelayInterface->{'name'},
                'children' => \@childrenDhcpRelayInterface
            );

            push( @$childrenServiceDhcp_Relay, \%hashDhcpRelayInterface );

            $xcp->copy_node( $childrenServiceDhcpRelay, \@childrenDhcpRelayInterface, 'server' );
            $xcp->copy_node( $childrenServiceDhcpRelay, \@childrenDhcpRelayInterface,
                'relay-options' );
        }
    }

    $xcp->comment_out_child( $hashServiceChildren, 'dhcp-relay' );
    return;
}

sub migrate_service_dhcp_server_1_to_0 {
    my ($file) = @_;
    $xcp->parse($file);

    my $hashServiceDhcpServer = $xcp->get_node( [ 'service', 'dhcp-server' ] );
    return if !defined($hashServiceDhcpServer);
    my $childrenServiceDhcpServer = $hashServiceDhcpServer->{'children'};
    return if !defined($childrenServiceDhcpServer);

    my @multis = $xcp->copy_multis( $childrenServiceDhcpServer, 'shared-network-name' );
    foreach my $multi (@multis) {
        foreach my $childSharedNetworkName ( @{ $multi->{'children'} // [] } ) {
            add_names_1_to_0( $childrenServiceDhcpServer, $multi, $childSharedNetworkName );
        }
        $xcp->comment_out_child( $childrenServiceDhcpServer,
            "shared-network-name $multi->{'name'}" );
    }
    return;
}

# dhcp-server 1 to 0: a "name <shared network>" node for each ethernet
# address on the subnet <network>/<prefix> of shared network $multi
sub add_names_1_to_0 {
    my ( $childrenServiceDhcpServer, $multi, $childSharedNetworkName ) = @_;

    my ( $subnet, $prefix_length ) = ( $childSharedNetworkName->{'name'} =~ m{(\S*)/(\d*)}x );

    my $nodeInterfaces = $xcp->get_node( ['interfaces'] );
    return if !defined($nodeInterfaces);

    my @multisInterfacesEthernet = $xcp->copy_multis( $nodeInterfaces->{'children'}, 'ethernet' );
    foreach my $multiInterfacesEthernet (@multisInterfacesEthernet) {
        my @multisInterfacesEthernetAddress =
          $xcp->copy_multis( $multiInterfacesEthernet->{'children'}, 'address' );
        foreach my $multiInterfacesEthernetAddress (@multisInterfacesEthernetAddress) {
            my $nodePrefixLength =
              $xcp->find_child( $multiInterfacesEthernetAddress->{'children'}, 'prefix-length' );
            next if !defined($nodePrefixLength);
            next if ( $prefix_length // 0 ) != ( $nodePrefixLength->{'value'} // 0 );

            my $naip1 =
              NetAddr::IP->new( $multiInterfacesEthernetAddress->{'name'} . "/$prefix_length" );
            next if ( $subnet ne $naip1->network()->addr() );

            my @childrenServiceDhcpServerName = (
                {
                    'name'  => 'interface',
                    'value' => $multiInterfacesEthernet->{'name'}
                },
                {
                    'name'  => 'network-mask',
                    'value' => $prefix_length
                }
            );
            push(
                @$childrenServiceDhcpServer,
                {
                    'name'     => 'name ' . $multi->{'name'},
                    'children' => \@childrenServiceDhcpServerName
                }
            );
            copy_dhcp_server_options( $childSharedNetworkName->{'children'},
                \@childrenServiceDhcpServerName );
        }
    }
    return;
}

sub migrate_service_dhcp_server_0_to_1 {
    my ($file) = @_;
    $xcp->parse($file);

    my $hashServiceDhcpServer = $xcp->get_node( [ 'service', 'dhcp-server' ] );
    return if !defined($hashServiceDhcpServer);
    my $childrenServiceDhcpServer = $hashServiceDhcpServer->{'children'};
    return if !defined($childrenServiceDhcpServer);

    my @multis = $xcp->copy_multis( $childrenServiceDhcpServer, 'name' );
    foreach my $multi (@multis) {
        add_shared_network_0_to_1( $childrenServiceDhcpServer, $multi );
        $xcp->comment_out_child( $childrenServiceDhcpServer, "name $multi->{'name'}" );
    }
    return;
}

# dhcp-server 0 to 1: a "shared-network-name" node for dhcp-server "name"
# $multi when its start address is on a subnet of its interface
sub add_shared_network_0_to_1 {
    my ( $childrenServiceDhcpServer, $multi ) = @_;

    my $nodeInterface   = $xcp->find_child( $multi->{'children'}, 'interface' );
    my $nodeNetworkMask = $xcp->find_child( $multi->{'children'}, 'network-mask' );
    my ($multiStart)    = $xcp->copy_multis( $multi->{'children'}, 'start' );
    return if !( defined($nodeInterface) && defined($nodeNetworkMask) && defined($multiStart) );

    my $stringInterface   = $nodeInterface->{'value'}   // q{};
    my $stringNetworkMask = $nodeNetworkMask->{'value'} // q{};
    my $stringStart       = $multiStart->{'name'}       // q{};
    return if ( $stringInterface eq q{} || $stringNetworkMask eq q{} || $stringStart eq q{} );
    $stringInterface   =~ s/"//gx;
    $stringNetworkMask =~ s/"//gx;

    my $nodeInterfacesEthernet = $xcp->get_node( [ 'interfaces', "ethernet $stringInterface" ] );
    return if !defined($nodeInterfacesEthernet);

    my @multisAddress = $xcp->copy_multis( $nodeInterfacesEthernet->{'children'}, 'address' );
    foreach my $multiAddress (@multisAddress) {
        my $naipInterfaceSubnet = interface_subnet($multiAddress);
        next if !defined($naipInterfaceSubnet);

        my $naipDHCPStart    = NetAddr::IP->new("$stringStart/$stringNetworkMask");
        my $stringDHCPSubnet = $naipDHCPStart->network()->addr();
        my $naipDHCPSubnet   = NetAddr::IP->new("$stringDHCPSubnet/$stringNetworkMask");
        next if !$naipDHCPSubnet->within($naipInterfaceSubnet);

        my @childrenSubnet;
        my @childrenSharedNetworkName = (
            {
                'name' => "subnet " . $naipDHCPSubnet->network()->addr() . '/' . $stringNetworkMask,
                'children' => \@childrenSubnet
            }
        );
        copy_dhcp_server_options( $multi->{'children'}, \@childrenSubnet );

        push(
            @$childrenServiceDhcpServer,
            {
                'name'     => 'shared-network-name ' . $multi->{'name'},
                'comment'  => $multi->{'comment'},
                'value'    => $multi->{'value'},
                'children' => \@childrenSharedNetworkName
            }
        );
    }
    return;
}

# the subnet of an interface's "address <a> { prefix-length <n> }" node, or
# undef if it has no prefix length
sub interface_subnet {
    my ($multiAddress) = @_;

    my $stringAddress    = $multiAddress->{'name'} // q{};
    my $nodePrefixLength = $xcp->find_child( $multiAddress->{'children'}, 'prefix-length' );
    return if !defined($nodePrefixLength);
    my $stringPrefixLength = $nodePrefixLength->{'value'} // q{};
    return if ( $stringAddress eq q{} || $stringPrefixLength eq q{} );

    my $naipInterfaceAddress  = NetAddr::IP->new("$stringAddress/$stringPrefixLength");
    my $stringInterfaceSubnet = $naipInterfaceAddress->network()->addr();
    return NetAddr::IP->new("$stringInterfaceSubnet/$stringPrefixLength");
}

# do nothing as the current version for dhcp-server in glendale was still 1
# the version was not changed to 2 in glendale and so the code for migration never got executed
# also, 'exclude' should have been removed from cli but was still on glendale, however, did nothing
# code to comment out exclude has been removed now when upgrading to version 2
# dhcp-server in glendale (still version 1) will get upgraded to version 2
# which does nothing and then 2 to hollywood (version 3) on upgrade from glendale to hollywood
sub migrate_service_dhcp_server_1_to_2 {
    my ($file) = @_;
    $xcp->parse($file);
    return;
}

# This migration involves no changes to the configuration.
sub migrate_service_dhcp_server_2_to_1 {
    my ($file) = @_;
    $xcp->parse($file);
    return;
}

# service <from> { <from_port> <n> } becomes service <to> { <to_port> <n> }
sub move_http_port {
    my ( $from, $from_port, $to, $to_port ) = @_;

    my $hashService         = $xcp->get_node( ['service'] );
    my $hashServiceChildren = $hashService->{'children'};

    my $hashFrom = $xcp->get_node( [ 'service', $from ] );
    if ( defined($hashFrom) ) {
        my $http_port;
        my $hashFromPort = $xcp->find_child( $hashFrom->{'children'}, $from_port );
        if ( defined($hashFromPort) ) {
            $http_port = $hashFromPort->{'value'};
        }

        my @childrenTo;
        if ( defined($http_port) ) {
            push( @childrenTo, { 'name' => $to_port, 'value' => $http_port } );
        }
        push( @$hashServiceChildren, { 'name' => $to, 'children' => \@childrenTo } );
    }
    $xcp->comment_out_child( $hashServiceChildren, $from );
    return;
}

sub migrate_service_webgui_0_to_1 {
    my ($file) = @_;
    $xcp->parse($file);
    move_http_port( 'http', 'port', 'webgui', 'http-port' );
    return;
}

sub migrate_service_webgui_1_to_0 {
    my ($file) = @_;
    $xcp->parse($file);
    move_http_port( 'webgui', 'http-port', 'http', 'port' );
    return;
}
