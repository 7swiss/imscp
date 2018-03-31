# i-MSCP iMSCP::Listener::Dovecot::PFS listener file
# Copyright (C) 2017-2018 Laurent Declercq <l.declercq@nuxwin.com>
# Copyright (C) 2016-2017 Rene Schuster <mail@reneschuster.de>
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
## Activates the Perfect Forward Secrecy logging.
#

package iMSCP::Listener::Dovecot::PFS;

our $VERSION = '1.0.1';

use strict;
use warnings;
use iMSCP::EventManager;
use iMSCP::File;
use iMSCP::Servers::Po;
use version;

#
## Please, don't edit anything below this line
#

version->parse( "$::imscpConfig{'PluginApi'}" ) >= version->parse( '1.6.0' ) or die(
    sprintf( "The 40_dovecot_pfs.pl listener file version %s requires i-MSCP >= 1.6.0", $VERSION )
);

iMSCP::EventManager->getInstance()->registerOne(
    'afterDovecotConfigure',
    sub {
        my $dovecotConfdir = iMSCP::Servers::Po->factory()->{'config'}->{'PO_CONF_DIR'};
        iMSCP::File->new( filename => "$dovecotConfdir/imscp.d/40_dovecot_pfs_listener.conf" )->set( <<'EOT' )->save();
login_log_format_elements = user=<%u> method=%m rip=%r lip=%l mpid=%e %c %k session=<%{session}>
EOT
    }
) if index( $::imscpConfig{'iMSCP::Servers::Po'}, '::Dovecot::' ) != -1;;

1;
__END__
