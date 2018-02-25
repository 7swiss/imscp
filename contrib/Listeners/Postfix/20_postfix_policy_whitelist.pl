# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2017-2018 Laurent Declercq <l.declercq@nuxwin.com>
# Copyright (C) 2013-2017 by Sascha Bay
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

#
## Setup Postfix whilelist tables for policy servers.
#

package iMSCP::Listener::Postfix::Policy::Whitelist;

our $VERSION = '1.0.2';

use strict;
use warnings;
use File::Basename;
use iMSCP::EventManager;
use iMSCP::Servers::Mta;

use version;

#
## Configuration variables
#

my $policyClientWhitelistTable = '/etc/postfix/policy_client_whitelist';
my $policyRecipientWhitelistTable = '/etc/postfix/policy_recipient_whitelist';

#
## Please, don't edit anything below this line
#

version->parse( "$::imscpConfig{'PluginApi'}" ) >= version->parse( '1.5.1' ) or die(
    sprintf( "The 20_postfix_policy_whitelist.pl listener file version %s requires i-MSCP >= 1.6.0", $VERSION )
);

iMSCP::EventManager->getInstance()->register(
    'afterPostfixConfigure',
    sub {
        my $mta = iMSCP::Servers::Mta->factory();
        my $dbDriver = $mta->getDbDriver( 'hash' );

        for my $table( $policyClientWhitelistTable, $policyRecipientWhitelistTable ) {
            my ($database, $storage) = fileparse( $table );
            $dbDriver->add( $database, undef, undef, $storage );
        }

        $mta->postconf(
            smtpd_recipient_restrictions => {
                action => 'add',
                values => [
                    "check_client_access hash:$policyClientWhitelistTable",
                    "check_recipient_access hash:$policyRecipientWhitelistTable"
                ],
                before => qr/permit/,
            }
        );
    },
    -99
) if index( $::imscpConfig{'iMSCP::Servers::Mta'}, '::Postfix::' ) != -1;

1;
__END__
