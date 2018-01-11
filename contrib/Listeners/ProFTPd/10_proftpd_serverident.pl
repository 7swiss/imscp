# i-MSCP iMSCP::Listener::ProFTPd::ServerIdent listener file
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
## Show custom server identification message
## See See http://www.proftpd.org/docs/directives/linked/config_ref_ServerIdent.html
#

package iMSCP::Listener::ProFTPd::ServerIdent;

our $VERSION = '1.0.2';

use strict;
use warnings;
use iMSCP::EventManager;
use iMSCP::TemplateParser qw/ processByRef /;
use version;

#
## Configuration parameters
#

# Server identification message to display when a client connect
my $SERVER_IDENT_MESSAGE = 'i-MSCP FTP server.';

#
## Please, don't edit anything below this line
#

version->parse( "$main::imscpConfig{'PluginApi'}" ) >= version->parse( '1.5.1' ) or die(
    sprintf( "The 10_proftpd_serverident.pl listener file version %s requires i-MSCP >= 1.6.0", $VERSION )
);

iMSCP::EventManager->getInstance()->register(
    'beforeProftpdBuildConfFile',
    sub {
        my ($tplContent, $tplName) = @_;

        return 0 unless $tplName eq 'proftpd.conf';

        $SERVER_IDENT_MESSAGE =~ s%("|\\)%\\$1%g;
        processByRef( { SERVER_IDENT_MESSAGE => qq/"$SERVER_IDENT_MESSAGE"/ }, $tplContent );
        0;
    }
) if index( $main::imscpConfig{'iMSCP::Servers::Ftpd'}, '::Proftpd::' ) != -1;

1;
__END__
