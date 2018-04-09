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
## Setup Postfix sender canonical maps.
#

package iMSCP::Listener::Postfix::Sender::Canonical;

our $VERSION = '1.0.3';

use strict;
use warnings;
use File::Basename;
use iMSCP::EventManager;
use iMSCP::Servers::Mta;
use version;

#
## Configuration variables
#

my $postfixSenderCanoncial = '/etc/postfix/sender_canonical';

#
## Please, don't edit anything below this line
#

version->parse( "$::imscpConfig{'PluginApi'}" ) >= version->parse( '1.6.0' ) or die(
    sprintf( "The 40_postfix_sender_canonical.pl listener file version %s requires i-MSCP >= 1.6.0", $VERSION )
);

iMSCP::EventManager->getInstance()->register( 'afterPostfixConfigure', sub
{
    my ( $database, $storage ) = fileparse( $postfixSenderCanoncial );
    my $mta = iMSCP::Servers::Mta->factory();
    $mta->getDbDriver( 'hash' )->add( $database, undef, undef, $storage );
    $mta->postconf(
        sender_canonical_maps => {
            action => 'add',
            values => [ "hash:$postfixSenderCanoncial" ]
        }
    );
}, -99 ) if index( $::imscpConfig{'iMSCP::Servers::Mta'}, '::Postfix::' ) != -1;

1;
__END__
