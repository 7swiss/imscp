# i-MSCP iMSCP::Listener::System::Mount::Userwebdir listener file
# Copyright (C) 2010-2018 Laurent Declercq <l.declercq@nuxwin.com>
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
## Remount your own USER_WEB_DIR to USER_WEB_DIR. For instance '/home/virtual' to '/var/www/virtual'
## Note that when using this listener, you must not add the mount entry in the system /etc/fstab file.
## Listener file compatible with i-MSCP >= 1.3.4
#

package iMSCP::Listener::System::Mount::Userwebdir;

our $VERSION = '1.0.1';

use strict;
use warnings;
use iMSCP::EventManager;
use iMSCP::Mount qw/ mount umount addMountEntry /;

#
## Configuration parameters
#

# Path to your own USER_WEB_DIR  directory
my $USER_WEB_DIR = '/home/virtual';

#
## Please don't edit anything below this line
#

iMSCP::EventManager->getInstance()->register(
    'afterSetupInstallFiles',
    sub {
        umount( $::imscpConfig{'USER_WEB_DIR'} );
        mount( {
            fs_spec    => $USER_WEB_DIR,
            fs_file    => $::imscpConfig{'USER_WEB_DIR'},
            fs_vfstype => 'none',
            fs_mntops  => 'rbind,rslave'
        } );
        addMountEntry( "$USER_WEB_DIR $::imscpConfig{'USER_WEB_DIR'} none rbind,rslave" );
    }
);

1;
__END__
