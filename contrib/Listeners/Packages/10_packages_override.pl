# i-MSCP iMSCP::Listener::Packages::Override listener file
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
## Replaces package file with custom one.
#

package iMSCP::Listener::Packages::Override;

our $VERSION = '1.0.2';

use strict;
use warnings;
use iMSCP::EventManager;

# Path to your own package file
my $DISTRO_PACKAGES_FILE = '/path/to/your/own/package/file';

#
## Please don't edit anything below this line
#

iMSCP::EventManager->getInstance()->register( 'onBuildPackageList', sub {
    my ( $pkgFile ) = @_;
    ${ $pkgFile } = $DISTRO_PACKAGES_FILE;
} );

1;
__END__
