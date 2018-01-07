=head1 NAME

 iMSCP::Packages::FileManager::MonstaFTP::MonstaFTP - i-MSCP package

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2018 by Laurent Declercq <l.declercq@nuxwin.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

package iMSCP::Packages::FileManager::MonstaFTP::MonstaFTP;

use strict;
use warnings;
use Class::Autouse qw/ :nostat iMSCP::Packages::FileManager::MonstaFTP::Installer iMSCP::Packages::FileManager::MonstaFTP::Uninstaller /;
use parent 'iMSCP::Common::Singleton';

=head1 DESCRIPTION

 i-MSCP MonstaFTP package.

 MonstaFTP is a web-based FTP client written in PHP.

 Project homepage: http://www.monstaftp.com//

=head1 PUBLIC METHODS

=over 4

=item preinstall( )

 Process preinstall tasks

 Return int 0 on success, other on failure

=cut

sub preinstall
{
    my ($self) = @_;

    iMSCP::Packages::FileManager::MonstaFTP::Installer->getInstance( eventManager => $self->{'eventManager'} )->preinstall();
}

=item install( )

 Process install tasks

 Return int 0 on success, other on failure

=cut

sub install
{
    my ($self) = @_;

    iMSCP::Packages::FileManager::MonstaFTP::Installer->getInstance( eventManager => $self->{'eventManager'} )->install();
}

=item uninstall( )

 Process uninstall tasks

 Return int 0 on success, other on failure

=cut

sub uninstall
{
    my ($self) = @_;

    iMSCP::Packages::FileManager::MonstaFTP::Uninstaller->getInstance( eventManager => $self->{'eventManager'} )->uninstall();
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
