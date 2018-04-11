# i-MSCP iMSCP::Listener::Named::Global::NS listener file
# Copyright (C) 2016-2018 Laurent Declercq <l.declercq@nuxwin.com>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301 USA

#
# Listener file that allows to set identical NS entries in all zones
# Requires i-MSCP 1.3.8 or newer.
#
# Warning: Don't forget to declare your slave DNS servers to i-MSCP.
# Don't forget also to activate IPv6 support if needed. All this can
# be done by reconfiguring the named service as follow:
#
#   perl /var/www/imscp/backend/setup/imscp-reconfigure -dr named
#

package iMSCP::Listener::Named::Global::NS;

our $VERSION = '1.0.1';

use strict;
use warnings;
use iMSCP::EventManager;
use iMSCP::Template::Processor qw/ getBlocByRef processBlocByRef processVarsByRef /;
use iMSCP::Net;

#
## Configuration variables
#

# Zone defining name servers
# Warning: For IDN, you must use the Punycode notation.
my $ZONE_NAME = 'zone.tld';

# Name servers
# Replace entries with your own data and delete those which are not needed for
# your use case. The first two entries correspond to this server.
#
# Note that the name from first entry is used as name-server in SOA RR.
#
# Warning: For IDNs, you must use the Punycode notation.
my @NAMESERVERS = (
    [ "ns1.$ZONE_NAME", '<ipv4>' ], # MASTER DNS IP (IPv4 ; this server)
    [ "ns1.$ZONE_NAME", '<ipv6>' ], # MASTER DNS IP (IPv6 ; this server)
    [ 'ns2.name.tld', '<ipv4>' ],   # SLAVE DNS 1 IP (IPv4)
    [ 'ns2.name.tld', '<ipv6>' ],   # SLAVE DNS 1 IP (IPv6)
    [ 'ns3.name.tld', '<ipv4>' ],   # SLAVE DNS 2 IP (IPv4)
    [ 'ns3.name.tld', '<ipv6>' ]    # SLAVE DNS 2 IP (IPv6)
);

#
## Please, don't edit anything below this line
#

version->parse( "$::imscpConfig{'PluginApi'}" ) >= version->parse( '1.6.0' ) or die(
    sprintf( "The 10_named_global_ns.pl listener file version %s requires i-MSCP >= 1.6.0", $VERSION )
);

iMSCP::EventManager->getInstance()->register( 'beforeBindAddDomainDb', sub
{
    my ( $tpl, $moduleData ) = @_;

    # Override default SOA RR (for all zones)
    my $nameserver = ( @NAMESERVERS )[0]->[0];
    ${ $tpl } =~ s/\Qns1.{DOMAIN_NAME}.\E/$nameserver./gm;
    ${ $tpl } =~ s/\Qhostmaster.{DOMAIN_NAME}.\E/hostmaster.$ZONE_NAME./gm;

    # Set NS and glue record entries (for all zones)
    my $nsRecordB = getBlocByRef( '; dmn NS RECORD entry BEGIN.', '; dmn NS RECORD entry ENDING.', $tpl );
    my $glueRecordB = getBlocByRef( '; dmn NS GLUE RECORD entry BEGIN.', '; dmn NS GLUE RECORD entry ENDING.', $tpl );
    my ( $nsRecords, $glueRecords ) = ( '', '' );
    my $net = iMSCP::Net->getInstance();

    for my $ipAddrType ( qw/ ipv4 ipv6 / ) {
        for my $nameserverData ( @NAMESERVERS ) {
            my ( $name, $ipAddr ) = @{ $nameserverData };
            next unless $net->getAddrVersion( $ipAddr ) eq $ipAddrType;

            $name .= '.';

            processVarsByRef( \$nsRecordB, {
                NS_NAME => $name
            } );

            # Glue RR must be set only if $data->{'DOMAIN_NAME'] is equal to $ZONE_NAME
            # Note that if $name is out-of-zone, it will be automatically ignored by the 'named-compilezone'
            # command during the dump (expected behavior).
            processVarsByRef( \$glueRecordB, {
                NS_NAME    => $name,
                NS_IP_TYPE => $ipAddrType eq 'ipv4' ? 'A' : 'AAAA',
                NS_IP      => $ipAddr
            } ) unless $ZONE_NAME ne $moduleData->{'DOMAIN_NAME'};
        }
    }

    processVarsByRef( $tpl, '; dmn NS RECORD entry BEGIN.', '; dmn NS RECORD entry ENDING.', $nsRecords );
    processVarsByRef( $tpl, '; dmn NS GLUE RECORD entry BEGIN.', '; dmn NS GLUE RECORD entry ENDING.', $glueRecords );
} ) if index( $imscp::Config{'iMSCP::Servers::Named'}, '::Bind9::' ) != -1;

1;
__END__
