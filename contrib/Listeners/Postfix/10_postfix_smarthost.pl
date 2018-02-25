# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2018 Laurent Declercq <l.declercq@nuxwin.com>
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
## Configure Postfix to route all mails to a smarthost using SASL authentication.
#

package iMSCP::Listener::Postfix::Smarthost;

our $VERSION = '1.0.2';

use strict;
use warnings;
use iMSCP::EventManager;
use iMSCP::File;
use iMSCP::Servers::Mta;
use version;

#
## Configuration variables
#

my $relayhost = '[smtp.host.tld]';
my $relayport = '587';
my $saslAuthUser = '';
my $saslAuthPasswd = '';
my $saslPasswdDb = 'relay_passwd';

#
## Please, don't edit anything below this line unless you known what you're doing
#

version->parse( "$::imscpConfig{'PluginApi'}" ) >= version->parse( '1.5.1' ) or die(
    sprintf( "The 10_postfix_smarthost.pl listener file version %s requires i-MSCP >= 1.6.0", $VERSION )
);

iMSCP::EventManager->getInstance()->register( 'beforeInstallPackages', sub { push @{$_[0]}, 'libsasl2-modules'; } );
iMSCP::EventManager->getInstance()->register(
    'afterPostfixConfigure',
    sub {
        my $mta = iMSCP::Servers::Mta->factory();
        $mta->getDbDriver( 'cbd' )->add( $saslPasswdMapsName, "$relayhost:$relayport", "$saslAuthUser:$saslAuthPasswd" );
        $mta->postconf(
            # Relay parameter
            relayhost                  => { values => [ "$relayhost:$relayport" ] },
            # smtp SASL parameters
            smtp_sasl_type             => { values => [ 'cyrus' ] },
            smtp_sasl_auth_enable      => { values => [ 'yes' ] },
            smtp_sasl_password_maps    => { 'add', values => [ "cdb:$mta->{'config'}->{'MTA_DB_DIR'}/$saslPasswdDb" ] },
            smtp_sasl_security_options => { values => [ 'noanonymous' ] }
        );
    },
    -99
) if index( $::imscpConfig{'iMSCP::Servers::Mta'}, '::Postfix::' ) != -1;

1;
__END__
