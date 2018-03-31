# i-MSCP iMSCP::Listener::Named::OverrideDefaultRecords listener file
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
# Listener that allows overriding of default DNS records with custom DNS records
# - @   IN {IP_TYPE} {DOMAIN_IP}
# - www IN CNAME     @

package iMSCP::Listener::Named::OverrideDefaultRecords;

our $VERSION = '1.0.1';

use strict;
use warnings;
use iMSCP::Net;
use iMSCP::EventManager;
use version;

#
## Please, don't edit anything below this line
#

version->parse( "$::imscpConfig{'PluginApi'}" ) >= version->parse( '1.6.0' ) or die(
    sprintf( "The 10_named_override_default_rr.pl listener file version %s requires i-MSCP >= 1.6.0", $VERSION )
);

if ( index( $imscp::Config{'iMSCP::Servers::Named'}, '::Bind9::' ) != -1 ) {
    iMSCP::EventManager->getInstance()->register(
        'beforeBindAddCustomDNS',
        # Listener that is responsible to replace following default DNS records:
        # - @   IN {IP_TYPE} {DOMAIN_IP}
        # - www IN CNAME     @
        sub {
            my ($wrkDbFileContent, $data) = @_;

            return unless @{$data->{'DNS_RECORDS'}};

            my $domainIP = iMSCP::Net->getInstance()->isRoutableAddr( $data->{'DOMAIN_IP'} )
                ? $data->{'DOMAIN_IP'} : $data->{'BASE_SERVER_PUBLIC_IP'};

            for ( @{$data->{'DNS_RECORDS'}} ) {
                my ($name, $class, $type, $rdata) = @{$_};
                if ( $name =~ /^\Q$data->{'DOMAIN_NAME'}.\E(?:\s+\d+)?/ && $class eq 'IN' && ( $type eq 'A' || $type eq 'AAAA' )
                    && $rdata ne $domainIP
                ) {
                    # Remove default A or AAAA record for $data->{'DOMAIN_NAME'}
                    ${$wrkDbFileContent} =~ s/
                        ^(?:\@|\Q$data->{'DOMAIN_NAME'}.\E)(?:\s+\d+)?\s+IN\s+$type\s+\Q$domainIP\E\n
                        //gmx;

                    next;
                };

                if ( $name =~ /^www\Q.$data->{'DOMAIN_NAME'}.\E(?:\s+\d+)?/ && $class eq 'IN' && $type eq 'CNAME'
                    && $rdata ne $data->{'DOMAIN_NAME'}
                ) {
                    # Delete default www CNAME record for $data->{'DOMAIN_NAME'}
                    ${$wrkDbFileContent} =~ s/
                        ^www(?:\Q.$data->{'DOMAIN_NAME'}.\E)?\s+IN\s+CNAME\s+(?:\@|\Q$data->{'DOMAIN_NAME'}.\E)\n
                        //gmx;
                }
            }
        }
    )->register(
        'afterBindAddCustomDNS',
        # Listener that is responsible to re-add the default DNS records when needed.
        # i-MSCP Bind9 server impl. will not do it unless the domain is being fully
        # reconfigured
        sub {
            my ($wrkDbFileContent, $data) = @_;

            my $net = iMSCP::Net->getInstance();
            my $domainIP = $net->isRoutableAddr( $data->{'DOMAIN_IP'} ) ? $data->{'DOMAIN_IP'} : $data->{'BASE_SERVER_PUBLIC_IP'};
            my $rrType = $net->getAddrVersion( $domainIP ) eq 'ipv4' ? 'A' : 'AAAA';

            # Re-add default A or AAAA record for $data->{'DOMAIN_NAME'}
            if ( ${$wrkDbFileContent} !~ /^\Q$data->{'DOMAIN_NAME'}.\E(?:\s+\d+)?\s+IN\s+$rrType\s+/m ) {
                ${$wrkDbFileContent} .= "$data->{'DOMAIN_NAME'}.\t\tIN\t$rrType\t$domainIP\n";
            }

            # Re-add default www CNAME record for $data->{'DOMAIN_NAME'}
            if ( ${$wrkDbFileContent} !~ /^www\Q.$data->{'DOMAIN_NAME'}.\E(?:\s+\d+)?\s+IN\s+CNAME\s+/m ) {
                ${$wrkDbFileContent} .= "www.$data->{'DOMAIN_NAME'}.\t\tIN\tCNAME\t$data->{'DOMAIN_NAME'}.\n";
            }
        }
    );
}

1;
__END__
