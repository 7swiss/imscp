# i-MSCP iMSCP::Listener::Roundcube::TLS listener file
# Copyright (C) 2017-2018 Laurent Declercq <l.declercq@nuxwin.com>
# Copyright (C) 2015-2017 Rene Schuster <mail@reneschuster.de>
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
## Changes the Roundcube Webmail configuration to connect through TLS.
#

package iMSCP::Listener::Roundcube::TLS;

our $VERSION = '1.0.1';

use strict;
use warnings;
use iMSCP::EventManager;

#
## Please, don't edit anything below this line unless you known what you're doing
#

iMSCP::EventManager->getInstance()->register(
    'afterSetupTasks',
    sub {
        my $file = iMSCP::File->new( filename => "$::imscpConfig{'GUI_PUBLIC_DIR'}/tools/webmail/config/config.inc.php" );
        ${$file->getAsRef()} =~ s/(\$config\['(?:default_host|smtp_server)?'\]\s+=\s+').*(';)/$1tls:\/\/$::imscpConfig{'BASE_SERVER_VHOST'}$2/g;
        $file->save();
    }
)->register(
    'beforeUpdateRoundCubeMailHostEntries',
    sub {
        my ($hostname) = @_;
        ${$hostname} = $::imscpConfig{'BASE_SERVER_VHOST'};
    }
);

1;
__END__
