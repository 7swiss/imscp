=head1 NAME

 iMSCP::Servers::Cron::Vixie::Debian - i-MSCP (Debian) Systemd cron server implementation

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

package iMSCP::Servers::Cron::Systemd::Debian;

use strict;
use warnings;
use Class::Autouse qw/ :nostat iMSCP::Service /;
use iMSCP::Debug qw/ error /;
use parent 'iMSCP::Servers::Cron::Vixie::Debian';

=head1 DESCRIPTION

 i-MSCP (Debian) systemd cron server implementation.
 
 See SYSTEMD.CRON(7) manpage.

=head1 PUBLIC METHODS

=over 4

=item postinstall( )

 See iMSCP::Servers::Cron::Vixie::Debian::Postinstall()

=cut

sub postinstall
{
    my ($self) = @_;

    eval { iMSCP::Service->getInstance()->enable( 'cron.target' ); };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    $self->{'eventManager'}->registerOne(
        'beforeSetupRestartServices',
        sub {
            push @{$_[0]}, [ sub { $self->start() }, $self->getHumanizedServerName() ];
            0;
        },
        $self->getPriority()
    );
}

=item start( )

 See iMSCP::Servers::Abstract::start()

=cut

sub start
{
    my ($self) = @_;

    eval { iMSCP::Service->getInstance()->start( 'cron.target' ); };
    if ( $@ ) {
        die( $@ );
        return 1;
    }

    0;
}

=item stop( )

 See iMSCP::Servers::Cron::Vixie::Debian::stop()

=cut

sub stop
{
    my ($self) = @_;

    eval { iMSCP::Service->getInstance()->stop( 'cron.target' ); };
    if ( $@ ) {
        die( $@ );
        return 1;
    }

    0;
}

=item restart( )

 See iMSCP::Servers::Cron::Vixie::Debian::restart()

=cut

sub restart
{
    my ($self) = @_;

    eval { iMSCP::Service->getInstance()->restart( 'cron.target' ); };
    if ( $@ ) {
        die( $@ );
        return 1;
    }

    0;
}

=item reload( )

 See iMSCP::Servers::Cron::Vixie::Debian::reload()

=cut

sub reload
{
    my ($self) = @_;

    # Job type reload is not applicable for unit cron.target, do a restart instead
    $self->restart();
}

=item getHumanizedServerName( )

 See iMSCP::Servers::Abstract::getHumanizedServerName()

=cut

sub getHumanizedServerName
{
    my ($self) = @_;

    'Cron (Systemd)';
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
