=head1 NAME

 iMSCP::Servers::Mta::Postfix::Abstract - i-MSCP Postfix server abstract implementation

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

package iMSCP::Servers::Mta::Postfix::Abstract;

use strict;
use warnings;
use autouse Fcntl => qw/ O_RDONLY /;
use autouse 'iMSCP::Rights' => qw/ setRights /;
use autouse 'iMSCP::TemplateParser' => qw/ processByRef /;
use Carp qw/ croak /;
use Class::Autouse qw/ :nostat iMSCP::Getopt iMSCP::Net iMSCP::SystemGroup iMSCP::SystemUser /;
use File::Basename;
use File::Temp;
use iMSCP::Config;
use iMSCP::Debug qw/ debug error getMessageByType /;
use iMSCP::Dir;
use iMSCP::Execute qw/ execute executeNoWait /;
use iMSCP::File;
use Tie::File;
use parent 'iMSCP::Servers::Mta';

=head1 DESCRIPTION

 i-MSCP Postfix server abstract implementation.

=head1 PUBLIC METHODS

=over 4

=item preinstall( )

 See iMSCP::Servers::Abstract::preinstall()

=cut

sub preinstall
{
    my ($self) = @_;

    my $rs = $self->SUPER::preinstall();
    $rs ||= $self->_createUserAndGroup();
    $rs ||= $self->_makeDirs();

}

=item install( )

 See iMSCP::Servers::Abstract::install()

=cut

sub install
{
    my ($self) = @_;

    my $rs = $self->_setVersion();
    $rs ||= $self->_createPostfixMaps();
    $rs ||= $self->_buildConf();
    $rs ||= $self->_buildAliasesDb();
}

=item postinstall( )

 See iMSCP::Servers::Abstract::postinstall()

=cut

sub postinstall
{
    my ($self) = @_;

    $self->{'eventManager'}->registerOne(
        'beforeSetupRestartServices',
        sub {
            for ( keys %{$self->{'_postmap'}} ) {
                if ( $self->{'_maps'}->{$_} ) {
                    my $rs = $self->{'_maps'}->{$_}->mode( 0640 );
                    return $rs if $rs;
                }

                my $rs = $self->postmap( $_ );
                return $rs if $rs;
            }
            0;
        },
        $self->getPriority()
    );

    $self->SUPER::postinstall();
}

=item uninstall( )

 See iMSCP::Servers::Abstract::uninstall()

=cut

sub uninstall
{
    my ($self) = @_;

    my $rs = $self->_removeUser();
    $rs ||= $self->_removeFiles();
}

=item setEnginePermissions( )

 Set engine permissions

 Return int 0 on success, other on failure

=cut

sub setEnginePermissions
{
    my ($self) = @_;
    # eg. /etc/postfix/main.cf
    my $rs = setRights( $self->{'config'}->{'POSTFIX_CONF_FILE'},
        {
            user  => $main::imscpConfig{'ROOT_USER'},
            group => $main::imscpConfig{'ROOT_GROUP'},
            mode  => '0644'
        }
    );
    # eg. /etc/postfix/master.cf
    $rs ||= setRights( $self->{'config'}->{'POSTFIX_MASTER_CONF_FILE'},
        {
            user  => $main::imscpConfig{'ROOT_USER'},
            group => $main::imscpConfig{'ROOT_GROUP'},
            mode  => '0644'
        }
    );
    # eg. /etc/aliases
    $rs ||= setRights( $self->{'config'}->{'MTA_LOCAL_ALIAS_HASH'},
        {
            user  => $main::imscpConfig{'ROOT_USER'},
            group => $main::imscpConfig{'ROOT_GROUP'},
            mode  => '0644'
        }
    );
    # eg. /etc/postfix/imscp
    $rs ||= setRights( $self->{'config'}->{'MTA_VIRTUAL_CONF_DIR'},
        {
            user      => $main::imscpConfig{'ROOT_USER'},
            group     => $main::imscpConfig{'ROOT_GROUP'},
            dirmode   => '0750',
            filemode  => '0640',
            recursive => 1
        }
    );
    # eg. /var/www/imscp/engine/messenger
    $rs ||= setRights( "$main::imscpConfig{'ENGINE_ROOT_DIR'}/messenger",
        {
            user      => $main::imscpConfig{'ROOT_USER'},
            group     => $main::imscpConfig{'IMSCP_GROUP'},
            dirmode   => '0750',
            filemode  => '0750',
            recursive => 1
        }
    );
    # eg. /var/mail/virtual
    $rs ||= setRights( $self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'},
        {
            user      => $self->{'config'}->{'MTA_MAILBOX_UID_NAME'},
            group     => $self->{'config'}->{'MTA_MAILBOX_GID_NAME'},
            dirmode   => '0750',
            filemode  => '0640',
            recursive => iMSCP::Getopt->fixPermissions
        }
    );
    # eg. /usr/sbin/maillogconvert.pl
    $rs ||= setRights( $self->{'config'}->{'MAIL_LOG_CONVERT_PATH'},
        {
            user  => $main::imscpConfig{'ROOT_USER'},
            group => $main::imscpConfig{'ROOT_GROUP'},
            mode  => '0750'
        }
    );
}

=item getGenericServerName( )

 See iMSCP::Servers::Abstract::getEventServerName()

=cut

sub getEventServerName
{
    my ($self) = @_;

    'Postfix';
}

=item getHumanServerName( )

 See iMSCP::Servers::Abstract::getHumanServerName()

=cut

sub getHumanServerName
{
    my ($self) = @_;

    sprintf( 'Postfix %s', $self->getVersion());
}

=item getVersion( )

 See iMSCP::Servers::Abstract::getVersion()

=cut

sub getVersion
{
    my ($self) = @_;

    $self->{'config'}->{'POSTFIX_VERSION'};
}

=item addDomain( \%moduleData )

 See iMSCP::Servers::Mta::addDomain()

=cut

sub addDomain
{
    my ($self, $moduleData) = @_;

    # Do not list `SERVER_HOSTNAME' in BOTH `mydestination' and `virtual_mailbox_domains'
    return 0 if $moduleData->{'DOMAIN_NAME'} eq $main::imscpConfig{'SERVER_HOSTNAME'};

    my $rs = $self->{'eventManager'}->trigger( 'beforePostfixAddDomain', $moduleData );
    $rs ||= $self->deleteMapEntry( $self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'}, qr/\Q$moduleData->{'DOMAIN_NAME'}\E\s+[^\n]*/ );
    $rs ||= $self->deleteMapEntry( $self->{'config'}->{'MTA_RELAY_HASH'}, qr/\Q$moduleData->{'DOMAIN_NAME'}\E\s+[^\n]*/ );

    if ( $moduleData->{'MAIL_ENABLED'} ) { # Mail is managed by this server
        $rs ||= $self->addMapEntry( $self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'}, "$moduleData->{'DOMAIN_NAME'}\tOK" );
    } elsif ( $moduleData->{'EXTERNAL_MAIL'} eq 'on' ) { # Mail is managed by external server
        $rs ||= $self->addMapEntry( $self->{'config'}->{'MTA_RELAY_HASH'}, "$moduleData->{'DOMAIN_NAME'}\tOK" );
    }

    $rs ||= $self->{'eventManager'}->trigger( 'afterPostfixAddDomain', $moduleData );
}

=item disableDomain( \%moduleData )

 See iMSCP::Servers::Mta::disableDomain()

=cut

sub disableDomain
{
    my ($self, $moduleData) = @_;

    return 0 if $moduleData->{'DOMAIN_NAME'} eq $main::imscpConfig{'SERVER_HOSTNAME'};

    my $rs = $self->{'eventManager'}->trigger( 'beforePostfixDisableDomain', $moduleData );
    $rs ||= $self->deleteMapEntry( $self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'}, qr/\Q$moduleData->{'DOMAIN_NAME'}\E\s+[^\n]*/ );
    $rs ||= $self->deleteMapEntry( $self->{'config'}->{'MTA_RELAY_HASH'}, qr/\Q$moduleData->{'DOMAIN_NAME'}\E\s+[^\n]*/ );
    $rs ||= $self->{'eventManager'}->trigger( 'afterPostfixDisableDomain', $moduleData );
}

=item deleteDomain( \%moduleData )

 See iMSCP::Servers::Mta::deleteDomain()

=cut

sub deleteDomain
{
    my ($self, $moduleData) = @_;

    my $rs = $self->{'eventManager'}->trigger( 'beforePostfixDeleteDomain', $moduleData );
    $rs ||= $self->deleteMapEntry( $self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'}, qr/\Q$moduleData->{'DOMAIN_NAME'}\E\s+[^\n]*/ );
    $rs ||= $self->deleteMapEntry( $self->{'config'}->{'MTA_RELAY_HASH'}, qr/\Q$moduleData->{'DOMAIN_NAME'}\E\s+[^\n]*/ );
    return $rs if $rs;

    eval { iMSCP::Dir->new( dirname => "$self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}/$moduleData->{'DOMAIN_NAME'}" )->remove(); };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    $self->{'eventManager'}->trigger( 'afterPostfixDeleteDomain', $moduleData );
}

=item addSubdomain( \%moduleData )

 See iMSCP::Servers::Mta::addSubdomain()

=cut

sub addSubdomain
{
    my ($self, $moduleData) = @_;

    # Do not list `SERVER_HOSTNAME' in BOTH `mydestination' and `virtual_mailbox_domains'
    return 0 if $moduleData->{'DOMAIN_NAME'} eq $main::imscpConfig{'SERVER_HOSTNAME'};

    my $rs = $self->{'eventManager'}->trigger( 'beforePostfixAddSubdomain', $moduleData );
    $rs ||= $self->deleteMapEntry( $self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'}, qr/\Q$moduleData->{'DOMAIN_NAME'}\E\s+[^\n]*/ );
    $rs ||= $self->addMapEntry( $self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'}, "$moduleData->{'DOMAIN_NAME'}\tOK" ) if $moduleData->{'MAIL_ENABLED'};
    $rs ||= $self->{'eventManager'}->trigger( 'afterPostfixAddSubdomain', $moduleData );
}

=item disableSubdomain( \%moduleData )

 See iMSCP::Servers::Mta::disableSubdomain()

=cut

sub disableSubdomain
{
    my ($self, $moduleData) = @_;

    return 0 if $moduleData->{'DOMAIN_NAME'} eq $main::imscpConfig{'SERVER_HOSTNAME'};

    my $rs = $self->{'eventManager'}->trigger( 'beforePostfixDisableSubdomain', $moduleData );
    $rs ||= $self->deleteMapEntry( $self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'}, qr/\Q$moduleData->{'DOMAIN_NAME'}\E\s+[^\n]*/ );
    $rs ||= $self->{'eventManager'}->trigger( 'afterPostfixDisableSubdomain', $moduleData );
}

=item deleteSubdomain( \%moduleData )

 See iMSCP::Servers::Mta::deleteSubdomain()

=cut

sub deleteSubdomain
{
    my ($self, $moduleData) = @_;

    my $rs = $self->{'eventManager'}->trigger( 'beforePostfixDeleteSubdomain', $moduleData );
    $rs ||= $self->deleteMapEntry( $self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'}, qr/\Q$moduleData->{'DOMAIN_NAME'}\E\s+[^\n]*/ );
    return $rs if $rs;

    eval { iMSCP::Dir->new( dirname => "$self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}/$moduleData->{'DOMAIN_NAME'}" )->remove(); };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    $self->{'eventManager'}->trigger( 'afterPostfixDeleteSubdomain', $moduleData );
}

=item addMail( \%moduleData )

 See iMSCP::Servers::Mta::addMail()

=cut

sub addMail
{
    my ($self, $moduleData) = @_;

    my $rs = $self->{'eventManager'}->trigger( 'beforePostfixAddMail', $moduleData );
    return $rs if $rs;

    if ( $moduleData->{'MAIL_CATCHALL'} ) {
        $rs = $self->addMapEntry( $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'}, "$moduleData->{'MAIL_ADDR'}\t$moduleData->{'MAIL_CATCHALL'}" );
        return $rs if $rs;
    } else {
        my $isMailAccount = index( $moduleData->{'MAIL_TYPE'}, '_mail' ) != -1
            && $moduleData->{'DOMAIN_NAME'} ne $main::imscpConfig{'SERVER_HOSTNAME'};
        my $isForwardAccount = index( $moduleData->{'MAIL_TYPE'}, '_forward' ) != -1;

        return 0 unless $isMailAccount || $isForwardAccount;

        $rs = $self->deleteMapEntry( $self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'}, qr/\Q$moduleData->{'MAIL_ADDR'}\E\s+[^\n]*/ );
        $rs ||= $self->deleteMapEntry( $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'}, qr/\Q$moduleData->{'MAIL_ADDR'}\E\s+[^\n]*/ );
        return $rs if $rs;

        my $responderEntry = "moduleDatadata->{'MAIL_ACC'}\@imscp-arpl.$moduleData->{'DOMAIN_NAME'}";
        $rs ||= $self->deleteMapEntry( $self->{'config'}->{'MTA_TRANSPORT_HASH'}, qr/\Q$responderEntry\E\s+[^\n]*/ );
        return $rs if $rs;

        if ( $isMailAccount ) {
            my $maildir = "$self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}/$moduleData->{'DOMAIN_NAME'}/$moduleData->{'MAIL_ACC'}";

            # Create mailbox
            eval {
                for ( $moduleData->{'DOMAIN_NAME'}, "$moduleData->{'DOMAIN_NAME'}/$moduleData->{'MAIL_ACC'}" ) {
                    iMSCP::Dir->new( dirname => "$self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}/$_" )->make( {
                        user           => $self->{'config'}->{'MTA_MAILBOX_UID_NAME'},
                        group          => $self->{'config'}->{'MTA_MAILBOX_GID_NAME'},
                        mode           => 0750,
                        fixpermissions => iMSCP::Getopt->fixPermissions
                    } );
                }

                for ( qw/ cur new tmp / ) {
                    iMSCP::Dir->new( dirname => "$maildir/$_" )->make( {
                        user           => $self->{'config'}->{'MTA_MAILBOX_UID_NAME'},
                        group          => $self->{'config'}->{'MTA_MAILBOX_GID_NAME'},
                        mode           => 0750,
                        fixpermissions => iMSCP::Getopt->fixPermissions
                    } );
                }
            };
            if ( $@ ) {
                error( $@ );
                return 1;
            }

            # Add virtual mailbox map entry
            $rs = $self->addMapEntry(
                $self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'},
                "$moduleData->{'MAIL_ADDR'}\t$moduleData->{'DOMAIN_NAME'}/$moduleData->{'MAIL_ACC'}/"
            );
            return $rs if $rs;
        } else {
            eval {
                iMSCP::Dir->new(
                    dirname => "$self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}/$moduleData->{'DOMAIN_NAME'}/$moduleData->{'MAIL_ACC'}"
                )->remove();
            };
            if ( $@ ) {
                error( $@ );
                return 1;
            }
        }

        # Add virtual alias map entry
        $rs = $self->addMapEntry(
            $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'},
            $moduleData->{'MAIL_ADDR'} # Recipient
                . "\t" # Separator
                . join ',', (
                    # Mail account only case:
                    #  Postfix lookup in `virtual_alias_maps' first. Thus, if there
                    #  is a catchall defined for the domain, any mail for the mail
                    #  account will be catched by the catchall. To prevent this
                    #  behavior, we must also add an entry in the virtual alias map.
                    #
                    # Forward + mail account case:
                    #  we want keep local copy of inbound mails
                    ( $isMailAccount ? $moduleData->{'MAIL_ADDR'} : () ),
                    # Add forward addresses in case of forward account
                    ( $isForwardAccount ? $moduleData->{'MAIL_FORWARD'} : () ),
                    # Add autoresponder entry if it is enabled for this account
                    ( $moduleData->{'MAIL_HAS_AUTO_RESPONDER'} ? $responderEntry : () )
                )
        );
        return $rs if $rs;

        if ( $moduleData->{'MAIL_HAS_AUTO_RESPONDER'} ) {
            # Add transport map entry for autoresponder
            $rs = $self->addMapEntry( $self->{'config'}->{'MTA_TRANSPORT_HASH'}, "$responderEntry\timscp-arpl:" );
            return $rs if $rs;
        }
    }

    $self->{'eventManager'}->trigger( 'afterPostfixAddMail', $moduleData );
}

=item disableMail( \%moduleData )

 See iMSCP::Servers::Mta::disableMail()

=cut

sub disableMail
{
    my ($self, $moduleData) = @_;

    my $rs = $self->{'eventManager'}->trigger( 'beforePostfixDisableMail', $moduleData );
    return $rs if $rs;

    if ( $moduleData->{'MAIL_CATCHALL'} ) {
        $rs ||= $self->deleteMapEntry(
            $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'}, qr/\Q$moduleData->{'MAIL_ADDR'}\E\s+\Q$moduleData->{'MAIL_CATCHALL'}/
        );
    } else {
        $rs ||= $self->deleteMapEntry( $self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'}, qr/\Q$moduleData->{'MAIL_ADDR'}\E\s+[^\n]*/ );
        $rs ||= $self->deleteMapEntry( $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'}, qr/\Q$moduleData->{'MAIL_ADDR'}\E\s+[^\n]*/ );
        return $rs if $rs;

        my $responderEntry = "$moduleData->{'MAIL_ACC'}\@imscp-arpl.$moduleData->{'DOMAIN_NAME'}";
        $rs = $self->deleteMapEntry( $self->{'config'}->{'MTA_TRANSPORT_HASH'}, qr/\Q$responderEntry\E\s+[^\n]*/ );
    }

    $rs ||= $self->{'eventManager'}->trigger( 'afterPostfixDisableMail', $moduleData );
}

=item deleteMail( \%moduleData )

 See iMSCP::Servers::Mta::deleteMail()

=cut

sub deleteMail
{
    my ($self, $moduleData) = @_;

    my $rs = $self->{'eventManager'}->trigger( 'beforePostfixDeleteMail', $moduleData );
    return $rs if $rs;

    if ( $moduleData->{'MAIL_CATCHALL'} ) {
        $rs ||= $self->deleteMapEntry(
            $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'}, qr/\Q$moduleData->{'MAIL_ADDR'}\E\s+\Q$moduleData->{'MAIL_CATCHALL'}/
        );
    } else {
        $rs ||= $self->deleteMapEntry( $self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'}, qr/\Q$moduleData->{'MAIL_ADDR'}\E\s+[^\n]*/ );
        $rs ||= $self->deleteMapEntry( $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'}, qr/\Q$moduleData->{'MAIL_ADDR'}\E\s+[^\n]*/ );
        return $rs if $rs;

        my $responderEntry = "$moduleData->{'MAIL_ACC'}\@imscp-arpl.$moduleData->{'DOMAIN_NAME'}";
        $rs = $self->deleteMapEntry( $self->{'config'}->{'MTA_TRANSPORT_HASH'}, qr/\Q$responderEntry\E\s+[^\n]*/ );
        return $rs if $rs;

        eval {
            iMSCP::Dir->new(
                dirname => "$self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}/$moduleData->{'DOMAIN_NAME'}/$moduleData->{'MAIL_ACC'}"
            )->remove();
        };
        if ( $@ ) {
            error( $@ );
            return 1;
        }
    }

    $rs ||= $self->{'eventManager'}->trigger( 'afterPostfixDeleteMail', $moduleData );
}

=item getTraffic( \%trafficDb [, $logFile, \%trafficIndexDb ] )

 See iMSCP::Servers::Mta::getTraffic()

=cut

sub getTraffic
{
    my ($self, $trafficDb, $logFile, $trafficIndexDb) = @_;
    $logFile ||= "$main::imscpConfig{'TRAFF_LOG_DIR'}/$main::imscpConfig{'MAIL_TRAFF_LOG'}";

    unless ( -f $logFile ) {
        debug( sprintf( "SMTP %s log file doesn't exist. Skipping ...", $logFile ));
        return;
    }

    debug( sprintf( 'Processing SMTP %s log file', $logFile ));

    # We use an index database to keep trace of the last processed logs
    $trafficIndexDb or croak %{$trafficIndexDb}, 'iMSCP::Config', fileName => "$main::imscpConfig{'IMSCP_HOMEDIR'}/traffic_index.db", nocroak => 1;
    my ($idx, $idxContent) = ( $trafficIndexDb->{'smtp_lineNo'} || 0, $trafficIndexDb->{'smtp_lineContent'} );

    # Extract and standardize SMTP logs in temporary file, using
    # maillogconvert.pl script
    my $stdLogFile = File::Temp->new( UNLINK => 1 );
    my $rs = execute(
        "/usr/bin/nice -n 19 /usr/bin/ionice -c2 -n7 /usr/local/sbin/maillogconvert.pl standard < $logFile > $stdLogFile", undef, \my $stderr
    );
    $rs == 0 or croak( sprintf( "Couldn't standardize SMTP logs: %s", $stderr || 'Unknown error' ));

    tie my @logs, 'Tie::File', $stdLogFile, mode => O_RDONLY, memory => 0 or croak( sprintf( "Couldn't tie %s file in read-only mode", $logFile ));

    if ( exists $logs[$idx] && $logs[$idx] eq $idxContent ) {
        debug( sprintf( 'Skipping SMTP logs that were already processed (lines %d to %d)', 1, ++$idx ));
    } elsif ( $idxContent ne '' && substr( $logFile, -2 ) ne '.1' ) {
        debug( 'Log rotation has been detected. Processing last rotated log file first' );
        $self->getTraffic( $trafficDb, $logFile . '.1', $trafficIndexDb );
        $idx = 0;
    }

    if ( $#logs < $idx ) {
        debug( 'No new SMTP logs found for processing' );
        return;
    }

    debug( sprintf( 'Processing SMTP logs (lines %d to %d)', $idx+1, $#logs+1 ));

    # Extract SMTP traffic data
    #
    # Log line example
    # date       hour     from            to            relay_s            relay_r            proto  extinfo code size
    # 2017-04-17 13:31:50 from@domain.tld to@domain.tld relay_s.domain.tld relay_r.domain.tld SMTP   -       1    1001
    my $regexp = qr/\@(?<from>[^\s]+)[^\@]+\@(?<to>[^\s]+)\s+(?<relay_s>[^\s]+)\s+(?<relay_r>[^\s]+).*?(?<size>\d+)$/;

    # In term of memory usage, C-Style loop provide better results than using 
    # range operator in Perl-Style loop: for( @logs[$idx .. $#logs] ) ...
    for ( my $i = $idx; $i <= $#logs; $i++ ) {
        next unless $logs[$i] =~ /$regexp/;
        $trafficDb->{$+{'from'}} += $+{'size'} if exists $trafficDb->{$+{'from'}};
        $trafficDb->{$+{'to'}} += $+{'size'} if exists $trafficDb->{$+{'to'}};
    }

    return if substr( $logFile, -2 ) eq '.1';

    $trafficIndexDb->{'smtp_lineNo'} = $#logs;
    $trafficIndexDb->{'smtp_lineContent'} = $logs[$#logs];
}

=item addMapEntry( $mapPath [, $entry ] )

 Add the given entry into the given Postfix map

 Note: Without any $entry passed-in, the map will be simply created.

 Param string $mapPath Map file path
 Param string $entry OPTIONAL Map entry to add if any
 Return int 0 on success, other on failure

=cut

sub addMapEntry
{
    my ($self, $mapPath, $entry) = @_;

    my $file = eval { $self->_getMapFileObject( $mapPath ); };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    return 0 unless defined $entry;

    my $mapFileContentRef = $file->getAsRef();
    unless ( defined $mapFileContentRef ) {
        error( sprintf( "Couldn't read the %s file", $file->{'filename'} ));
        return 1;
    }

    my $rs = $self->{'eventManager'}->trigger( 'beforeAddPostfixMapEntry', $mapPath, $entry );
    return $rs if $rs;

    ${$mapFileContentRef} =~ s/^\Q$entry\E\n//gim;
    ${$mapFileContentRef} .= "$entry\n";

    $rs ||= $file->save();
    $self->{'_postmap'}->{$mapPath} ||= 1 unless $rs || $self->{'_postmap'}->{$mapPath};
    $rs ||= $self->{'eventManager'}->trigger( 'afterAddPostfixMapEntry', $mapPath, $entry );
}

=item deleteMapEntry( $mapPath, $entry )

 Delete the given entry from the given Postfix map

 Param string $mapPath Map file path
 Param Regexp $entry Regexp matching map entry to delete
 Return int 0 on success, other on failure

=cut

sub deleteMapEntry
{
    my ($self, $mapPath, $entry) = @_;

    my $file = eval { $self->_getMapFileObject( $mapPath ); };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    my $mapFileContentRef = $file->getAsRef();
    unless ( defined $mapFileContentRef ) {
        error( sprintf( "Couldn't read the %s file", $file->{'filename'} ));
        return 1;
    }

    my $rs = $self->{'eventManager'}->trigger( 'beforeDeletePostfixMapEntry', $mapPath, $entry );
    return $rs if $rs;

    if ( ${$mapFileContentRef} =~ s/^$entry\n//gim ) {
        $rs = $file->save();
        $self->{'_postmap'}->{$mapPath} = 1 unless $rs || $self->{'_postmap'}->{$mapPath};
        return $rs if $rs;
    }

    $self->{'eventManager'}->trigger( 'afterDeletePostfixMapEntry', $mapPath, $entry );
}

=item postmap( $mapPath [, $mapType = 'hash' ] )

 Postmap the given map

 Param string $mapPath Map path
 Param string $hashtype Map type (default: hash)
 Return int 0 on success, other on failure

=cut

sub postmap
{
    my (undef, $mapPath, $mapType) = @_;
    $mapType ||= 'hash';

    my $rs = execute( "postmap $mapType:$mapPath", \ my $stdout, \ my $stderr );
    debug( $stdout ) if $stdout;
    error( $stderr || 'Unknown error' ) if $rs;
    $rs;
}

=item postconf( $conffile, %params )

 Provides an interface to POSTCONF(1) for editing parameters in Postfix main.cf configuration file

 Param hash %params A hash where each key is a Postfix parameter name and the value, a hashes describing in order:
  - action : Action to be performed (add|replace|remove) -- Default add
  - values : An array containing parameter value(s) to add, replace or remove. For values to be removed, both strings and Regexp are supported.
  - empty  : OPTIONAL Flag that allows to force adding of empty parameter
  - before : OPTIONAL Option that allows to add values before the given value (expressed as a Regexp)
  - after  : OPTIONAL Option that allows to add values after the given value (expressed as a Regexp)

  `replace' action versus `remove' action
    The `replace' action replace the full value of the given parameter while the `remove' action only remove the specified value portion in the
    parameter value. Note that when the resulting value is an empty value, the paramerter is removed from the configuration file unless the `empty'
    flag has been specified.

  `before' and `after' options:
    The `before' and `after' options are only relevant for the `add' action. Note also that the `before' option has a highter precedence than the
    `after' option.
  
  Unknown postfix parameters
    Unknown Postfix parameter are silently ignored

  Usage example:

    Adding parameters

    Let's assume that we want add both, the `check_client_access <table>' value and the `check_recipient_access <table>' value to the
    `smtpd_recipient_restrictions' parameter, before the `check_policy_service ...' service. The following would do the job:

    iMSCP::Servers::Mta::Postfix::Abstract->getInstance(
        (
            smtpd_recipient_restrictions => {
                action => 'add',
                values => [ 'check_client_access <table>', 'check_recipient_access <table>' ],
                before => qr/check_policy_service\s+.*/,
            }
        )
    );
 
    Removing parameters

    iMSCP::Servers::Mta::Postfix::Abstract->getInstance(
        (
            smtpd_milters     => {
                action => 'remove',
                values => [ qr%\Qunix:/opendkim/opendkim.sock\E% ] # Using Regexp
            },
            non_smtpd_milters => {
                action => 'remove',
                values => [ 'unix:/opendkim/opendkim.sock' ] # Using string
            }
        )
    )

 Return int 0 on success, other failure

=cut

sub postconf
{
    my ($self, %params) = @_;

    eval {
        %params or croak( 'Missing parameters ' );

        my @pToDel = ();
        my $conffile = $self->{'config'}->{'POSTFIX_CONF_DIR'} || '/etc/postfix';
        my $time = time();

        # Avoid POSTCONF(1) being slow by waiting 2 seconds before next processing
        # See https://groups.google.com/forum/#!topic/list.postfix.users/MkhEqTR6yRM
        utime $time, $time-2, $self->{'config'}->{'POSTFIX_CONF_FILE'} or croak(
            sprintf( "Couldn't touch %s file: %s", $self->{'config'}->{'POSTFIX_CONF_FILE'} )
        );

        my ($stdout, $stderr);
        executeNoWait(
            [ 'postconf', '-c', $conffile, keys %params ],
            sub {
                return unless ( my $p, my $v ) = $_[0] =~ /^([^=]+)\s+=\s*(.*)/;

                my (@vls, @rpls) = ( split( /,\s*/, $v ), () );

                defined $params{$p}->{'values'} && ref $params{$p}->{'values'} eq 'ARRAY' or croak(
                    sprintf( "Missing or invalid `values' for the %s parameter. Expects an array of values", $p )
                );

                for $v( @{$params{$p}->{'values'}} ) {
                    if ( !$params{$p}->{'action'} || $params{$p}->{'action'} eq 'add' ) {
                        unless ( $params{$p}->{'before'} || $params{$p}->{'after'} ) {
                            next if grep( $_ eq $v, @vls );
                            push @vls, $v;
                            next;
                        }

                        # If the parameter already exists, we delete it as someone could want move it
                        @vls = grep( $_ ne $v, @vls );
                        my $regexp = $params{$p}->{'before'} || $params{$p}->{'after'};
                        ref $regexp eq 'Regexp' or croak( 'Invalid before|after option. Expects a Regexp' );
                        my ($idx) = grep ( $vls[$_] =~ /^$regexp$/, 0 .. ( @vls-1 ) );
                        defined $idx ? splice( @vls, ( $params{$p}->{'before'} ? $idx : ++$idx ), 0, $v ) : push @vls, $v;
                    } elsif ( $params{$p}->{'action'} eq 'replace' ) {
                        push @rpls, $v;
                    } elsif ( $params{$p}->{'action'} eq 'remove' ) {
                        @vls = ref $v eq 'Regexp' ? grep ($_ !~ $v, @vls) : grep ($_ ne $v, @vls);
                    } else {
                        croak( sprintf( 'Unknown action %s for the  %s parameter', $params{$p}->{'action'}, $p ));
                    }
                }

                my $forceEmpty = $params{$p}->{'empty'};
                $params{$p} = join ', ', @rpls ? @rpls : @vls;

                unless ( $forceEmpty || $params{$p} ne '' ) {
                    push @pToDel, $p;
                    delete $params{$p};
                }
            },
            sub { $stderr .= shift }
        ) == 0 or croak( $stderr || 'Unknown error' );

        if ( %params ) {
            my $cmd = [ 'postconf', '-e', '-c', $conffile ];
            while ( my ($param, $value) = each %params ) { push @{$cmd}, "$param=$value" };
            execute( $cmd, \$stdout, \$stderr ) == 0 or croak( $stderr || 'Unknown error' );
            debug( $stdout ) if $stdout;
        }

        if ( @pToDel ) {
            execute( [ 'postconf', '-X', '-c', $conffile, @pToDel ], \$stdout, \$stderr ) == 0 or croak( $stderr || 'Unknown error' );
            debug( $stdout ) if $stdout;
        };

        $self->{'reload'} ||= 1;
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=back

=head1 PRIVATE METHODS

=over 4

=item _init( )

 Initialize instance

 Return iMSCP::Servers::Mta::Postfix::Abstract

=cut

sub _init
{
    my ($self) = @_;

    ref $self ne __PACKAGE__ or croak( sprintf( 'The %s class is an abstract class which cannot be instantiated', __PACKAGE__ ));

    @{$self}{qw/ restart reload cfgDir /} = ( 0, 0, "$main::imscpConfig{'CONF_DIR'}/postfix" );
    $self->_mergeConfig() if defined $main::execmode && $main::execmode eq 'setup' && -f "$self->{'cfgDir'}/postfix.data.dist";
    tie %{$self->{'config'}},
        'iMSCP::Config',
        fileName    => "$self->{'cfgDir'}/postfix.data",
        readonly    => !( defined $main::execmode && $main::execmode eq 'setup' ),
        nodeferring => defined $main::execmode && $main::execmode eq 'setup';
    $self->{'_maps'} = {};
    $self->SUPER::_init();
}

=item _mergeConfig( )

 Merge distribution configuration with production configuration

 Return void, croak on failure

=cut

sub _mergeConfig
{
    my ($self) = @_;

    if ( -f "$self->{'cfgDir'}/postfix.data" ) {
        tie my %newConfig, 'iMSCP::Config', fileName => "$self->{'cfgDir'}/postfix.data.dist";
        tie my %oldConfig, 'iMSCP::Config', fileName => "$self->{'cfgDir'}/postfix.data", readonly => 1;

        debug( 'Merging old configuration with new configuration ...' );

        while ( my ($key, $value) = each( %oldConfig ) ) {
            next unless exists $newConfig{$key};
            $newConfig{$key} = $value;
        }

        untie ( %newConfig );
        untie( %oldConfig );
    }

    iMSCP::File->new( filename => "$self->{'cfgDir'}/postfix.data.dist" )->moveFile( "$self->{'cfgDir'}/postfix.data" ) == 0 or croak(
        getMessageByType( 'error', { amount => 1, remove => 1 } ) || 'Unknown error'
    );
}

=item _getMapFileObject( mapPath )

 Get iMSCP::File object for the given postfix map

 Param string $mapPath Postfix map path
 Return iMSCP::File, croak on failure

=cut

sub _getMapFileObject
{
    my ($self, $mapPath) = @_;

    $self->{'_maps'}->{$mapPath} ||= do {
        my $file = iMSCP::File->new( filename => $mapPath );

        unless ( -f $mapPath ) {
            $file->set( <<"EOF"
# Postfix @{ [ basename( $mapPath ) ] } map - auto-generated by i-MSCP
#     DO NOT EDIT THIS FILE BY HAND -- YOUR CHANGES WILL BE OVERWRITTEN

EOF
            );
            $file->save() == 0 && $file->mode( 0640 ) == 0 or croak( getMessageByType( 'error', { amount => 1, remove => 1 } ) || 'Unknown error' );
            $self->{'_postmap'}->{$mapPath} ||= 1;
        }

        $file;
    }
}

=item _createUserAndGroup( )

 Create vmail user and mail group

 Return int 0 on success, other on failure

=cut

sub _createUserAndGroup
{
    my ($self) = @_;

    my $rs = iMSCP::SystemGroup->getInstance()->addSystemGroup( $self->{'config'}->{'MTA_MAILBOX_GID_NAME'}, 1 );
    return $rs if $rs;

    my $systemUser = iMSCP::SystemUser->new(
        username => $self->{'config'}->{'MTA_MAILBOX_UID_NAME'},
        group    => $self->{'config'}->{'MTA_MAILBOX_GID_NAME'},
        comment  => 'vmail user',
        home     => $self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'},
        system   => 1
    );
    $rs = $systemUser->addSystemUser();
    $rs ||= $systemUser->addToGroup( $main::imscpConfig{'IMSCP_GROUP'} );
}

=item _makeDirs( )

 Create directories

 Return int 0 on success, other on failure

=cut

sub _makeDirs
{
    my ($self) = @_;

    my @directories = (
        [
            $self->{'config'}->{'MTA_VIRTUAL_CONF_DIR'}, # eg. /etc/postfix/imscp
            $main::imscpConfig{'ROOT_USER'},
            $main::imscpConfig{'ROOT_GROUP'},
            0750
        ],
        [
            $self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}, # eg. /var/mail/virtual
            $self->{'config'}->{'MTA_MAILBOX_UID_NAME'},
            $self->{'config'}->{'MTA_MAILBOX_GID_NAME'},
            0750
        ]
    );

    eval {
        # Make sure to start with clean directory
        iMSCP::Dir->new( dirname => $self->{'config'}->{'MTA_VIRTUAL_CONF_DIR'} )->remove();

        for my $dir( @directories ) {
            iMSCP::Dir->new( dirname => $dir->[0] )->make( {
                user           => $dir->[1],
                group          => $dir->[2],
                mode           => $dir->[3],
                fixpermissions => iMSCP::Getopt->fixPermissions
            } );
        }
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=item _buildConf( )

 Build configuration file

 Return int 0 on success, other on failure

=cut

sub _buildConf
{
    my ($self) = @_;

    my $rs = $self->{'eventManager'}->trigger( 'beforePostfixBuildConf' );
    $rs ||= $self->_buildMasterCfFile();
    $rs ||= $self->_buildMainCfFile();
    $rs ||= $self->{'eventManager'}->trigger( 'afterPostfixBuildConf' );
}

=item _setVersion( )

 Set Postfix version

 Return 0 on success, other on failure

=cut

sub _setVersion
{
    my ($self) = @_;

    my $rs = execute( [ '/usr/sbin/postconf', '-d', '-h', 'mail_version' ], \ my $stdout, \ my $stderr );
    debug( $stderr || 'Unknown error' ) if $rs;
    return $rs if $rs;

    if ( $stdout !~ /^([\d.]+)/ ) {
        error( "Couldn't guess Postfix version from the `/usr/sbin/postconf -d -h mail_version` command output" );
        return 1;
    }

    $self->{'config'}->{'POSTFIX_VERSION'} = $1;
    debug( sprintf( 'Postfix version set to: %s', $stdout ));
    0;
}

=item _createPostfixMaps( )

 Ceate postfix maps

 Return int 0 on success, other on failure

=cut

sub _createPostfixMaps
{
    my ($self) = @_;

    my @lookupTables = (
        $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'}, $self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'},
        $self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'}, $self->{'config'}->{'MTA_TRANSPORT_HASH'},
        $self->{'config'}->{'MTA_RELAY_HASH'}
    );

    for ( @lookupTables ) {
        my $rs = $self->addMapEntry( $_ );
        return $rs if $rs;
    }

    0;
}

=item _buildAliasesDb( )

 Build aliases database

 Return int 0 on success, other on failure

=cut

sub _buildAliasesDb
{
    my ($self) = @_;

    my $rs = $self->{'eventManager'}->trigger( 'onLoadTemplate', 'postfix', 'aliases', \ my $cfgTpl, {} );
    return $rs if $rs;

    unless ( defined $cfgTpl ) {
        $cfgTpl = iMSCP::File->new( filename => $self->{'config'}->{'MTA_LOCAL_ALIAS_HASH'} )->get();
        $cfgTpl = '' unless defined $cfgTpl;
    }

    $rs = $self->{'eventManager'}->trigger( 'beforePostfixBuildAliasesDbFile', \ $cfgTpl, 'aliases' );
    return $rs if $rs;

    # Add alias for local root user
    $cfgTpl =~ s/^root:.*\n//gim;
    $cfgTpl .= 'root: ' . main::setupGetQuestion( 'DEFAULT_ADMIN_ADDRESS' ) . "\n";

    $rs = $self->{'eventManager'}->trigger( 'afterPostfixBuildAliasesDbFile', \ $cfgTpl, 'aliases' );
    return $rs if $rs;

    my $file = iMSCP::File->new( filename => $self->{'config'}->{'MTA_LOCAL_ALIAS_HASH'} );
    $file->set( $cfgTpl );

    $rs = $file->save();
    return $rs if $rs;

    $rs = execute( 'newaliases', \ my $stdout, \ my $stderr );
    debug( $stdout ) if $stdout;
    error( $stderr || 'Unknown error' ) if $rs;
    $rs;
}

=item _buildMasterCfFile( )

 Build master.cf file

 Return int 0 on success, other on failure

=cut

sub _buildMasterCfFile
{
    my ($self) = @_;

    my $serverData = {
        MTA_MAILBOX_UID_NAME => $self->{'config'}->{'MTA_MAILBOX_UID_NAME'},
        IMSCP_GROUP          => $main::imscpConfig{'IMSCP_GROUP'},
        ARPL_PATH            => $main::imscpConfig{'ROOT_DIR'} . "/engine/messenger/imscp-arpl-msgr"
    };

    my $rs = $self->{'eventManager'}->trigger( 'onLoadTemplate', 'postfix', 'master.cf', \ my $cfgTpl, $serverData );
    return $rs if $rs;

    unless ( defined $cfgTpl ) {
        $cfgTpl = iMSCP::File->new( filename => "$self->{'cfgDir'}/master.cf" )->get();
        unless ( defined $cfgTpl ) {
            error( sprintf( "Couldn't read the %s file", "$self->{'cfgDir'}/master.cf" ));
            return 1;
        }
    }

    $rs = $self->{'eventManager'}->trigger( 'beforePostfixBuildMasterCfFile', \ $cfgTpl, 'master.cf' );
    return $rs if $rs;

    processByRef( $serverData, \$cfgTpl );

    $rs = $self->{'eventManager'}->trigger( 'afterPostfixBuildMasterCfFile', \ $cfgTpl, 'master.cf' );
    return $rs if $rs;

    my $file = iMSCP::File->new( filename => $self->{'config'}->{'POSTFIX_MASTER_CONF_FILE'} );
    $file->set( $cfgTpl );
    $file->save();
}

=item _buildMainCfFile( )

 Build main.cf file

 Return int 0 on success, other on failure

=cut

sub _buildMainCfFile
{
    my ($self) = @_;

    my $baseServerIp = main::setupGetQuestion( 'BASE_SERVER_IP' );
    my $baseServerIpType = iMSCP::Net->getInstance->getAddrVersion( $baseServerIp );
    my $gid = getgrnam( $self->{'config'}->{'MTA_MAILBOX_GID_NAME'} );
    my $uid = getpwnam( $self->{'config'}->{'MTA_MAILBOX_UID_NAME'} );
    my $hostname = main::setupGetQuestion( 'SERVER_HOSTNAME' );
    my $serverData = {
        MTA_INET_PROTOCOLS       => $baseServerIpType,
        MTA_SMTP_BIND_ADDRESS    => ( $baseServerIpType eq 'ipv4' && $baseServerIp ne '0.0.0.0' ) ? $baseServerIp : '',
        MTA_SMTP_BIND_ADDRESS6   => ( $baseServerIpType eq 'ipv6' ) ? $baseServerIp : '',
        MTA_HOSTNAME             => $hostname,
        MTA_LOCAL_DOMAIN         => "$hostname.local",
        MTA_VERSION              => $main::imscpConfig{'Version'}, # Fake data expected
        MTA_TRANSPORT_HASH       => $self->{'config'}->{'MTA_TRANSPORT_HASH'},
        MTA_LOCAL_MAIL_DIR       => $self->{'config'}->{'MTA_LOCAL_MAIL_DIR'},
        MTA_LOCAL_ALIAS_HASH     => $self->{'config'}->{'MTA_LOCAL_ALIAS_HASH'},
        MTA_VIRTUAL_MAIL_DIR     => $self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'},
        MTA_VIRTUAL_DMN_HASH     => $self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'},
        MTA_VIRTUAL_MAILBOX_HASH => $self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'},
        MTA_VIRTUAL_ALIAS_HASH   => $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'},
        MTA_RELAY_HASH           => $self->{'config'}->{'MTA_RELAY_HASH'},
        MTA_MAILBOX_MIN_UID      => $uid,
        MTA_MAILBOX_UID          => $uid,
        MTA_MAILBOX_GID          => $gid
    };

    my $rs = $self->{'eventManager'}->trigger( 'onLoadTemplate', 'postfix', 'main.cf', \ my $cfgTpl, $serverData );
    return $rs if $rs;

    unless ( defined $cfgTpl ) {
        $cfgTpl = iMSCP::File->new( filename => "$self->{'cfgDir'}/main.cf" )->get();
        unless ( defined $cfgTpl ) {
            error( sprintf( "Couldn't read the %s file", "$self->{'cfgDir'}/main.cf" ));
            return 1;
        }
    }

    $rs = $self->{'eventManager'}->trigger( 'beforePostfixBuildMainCfFile', \$cfgTpl, 'main.cf' );
    return $rs if $rs;

    processByRef( $serverData, \$cfgTpl );

    $rs = $self->{'eventManager'}->trigger( 'afterPostfixBuildMainCfFile', \ $cfgTpl, 'main.cf' );
    return $rs if $rs;

    my $file = iMSCP::File->new( filename => $self->{'config'}->{'POSTFIX_CONF_FILE'} );
    $file->set( $cfgTpl );

    $rs = $file->save();
    return $rs if $rs;

    # Add TLS parameters if required
    return 0 unless main::setupGetQuestion( 'SERVICES_SSL_ENABLED' ) eq 'yes';

    $self->{'eventManager'}->register(
        'afterPostfixBuildConf',
        sub {
            my %params = (
                # smtpd TLS parameters (opportunistic)
                smtpd_tls_security_level         => {
                    action => 'replace',
                    values => [ 'may' ]
                },
                smtpd_tls_ciphers                => {
                    action => 'replace',
                    values => [ 'high' ]
                },
                smtpd_tls_exclude_ciphers        => {
                    action => 'replace',
                    values => [ 'aNULL', 'MD5' ]
                },
                smtpd_tls_protocols              => {
                    action => 'replace',
                    values => [ '!SSLv2', '!SSLv3' ]
                },
                smtpd_tls_loglevel               => {
                    action => 'replace',
                    values => [ '0' ]
                },
                smtpd_tls_cert_file              => {
                    action => 'replace',
                    values => [ "$main::imscpConfig{'CONF_DIR'}/imscp_services.pem" ]
                },
                smtpd_tls_key_file               => {
                    action => 'replace',
                    values => [ "$main::imscpConfig{'CONF_DIR'}/imscp_services.pem" ]
                },
                smtpd_tls_auth_only              => {
                    action => 'replace',
                    values => [ 'no' ]
                },
                smtpd_tls_received_header        => {
                    action => 'replace',
                    values => [ 'yes' ]
                },
                smtpd_tls_session_cache_database => {
                    action => 'replace',
                    values => [ 'btree:/var/lib/postfix/smtpd_scache' ]
                },
                smtpd_tls_session_cache_timeout  => {
                    action => 'replace',
                    values => [ '3600s' ]
                },
                # smtp TLS parameters (opportunistic)
                smtp_tls_security_level          => {
                    action => 'replace',
                    values => [ 'may' ]
                },
                smtp_tls_ciphers                 => {
                    action => 'replace',
                    values => [ 'high' ]
                },
                smtp_tls_exclude_ciphers         => {
                    action => 'replace',
                    values => [ 'aNULL', 'MD5' ]
                },
                smtp_tls_protocols               => {
                    action => 'replace',
                    values => [ '!SSLv2', '!SSLv3' ]
                },
                smtp_tls_loglevel                => {
                    action => 'replace',
                    values => [ '0' ]
                },
                smtp_tls_CAfile                  => {
                    action => 'replace',
                    values => [ '/etc/ssl/certs/ca-certificates.crt' ]
                },
                smtp_tls_session_cache_database  => {
                    action => 'replace',
                    values => [ 'btree:/var/lib/postfix/smtp_scache' ]
                }
            );

            if ( version->parse( $self->{'config'}->{'POSTFIX_VERSION'} ) >= version->parse( '2.10.0' ) ) {
                $params{'smtpd_relay_restrictions'} = {
                    action => 'replace',
                    values => [ '' ],
                    empty  => 1
                };
            }

            if ( version->parse( $self->{'config'}->{'POSTFIX_VERSION'} ) >= version->parse( '3.0.0' ) ) {
                $params{'compatibility_level'} = {
                    action => 'replace',
                    values => [ '2' ]
                };
            }

            $self->postconf( %params );
        }
    );
}

=item _removeUser( )

 Remove user

 Return int 0 on success, other on failure

=cut

sub _removeUser
{
    iMSCP::SystemUser->new( force => 'yes' )->delSystemUser( $_[0]->{'config'}->{'MTA_MAILBOX_UID_NAME'} );
}

=item _removeFiles( )

 Remove files

 Return int 0 on success, other or croak on failure

=cut

sub _removeFiles
{
    my ($self) = @_;

    eval {
        for ( $self->{'config'}->{'MTA_VIRTUAL_CONF_DIR'}, $self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'} ) {
            iMSCP::Dir->new( dirname => $_ )->remove();
        }
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    return 0 unless -f $self->{'config'}->{'MAIL_LOG_CONVERT_PATH'};

    iMSCP::File->new( filename => $self->{'config'}->{'MAIL_LOG_CONVERT_PATH'} )->delFile();
}

=item END

 Regenerate Postfix maps

=cut

END
    {
        return if $? || ( defined $main::execmode && $main::execmode eq 'setup' );

        return unless my $instance = __PACKAGE__->hasInstance();

        my ($ret, $rs) = ( 0, 0 );

        for ( keys %{$instance->{'_postmap'}} ) {
            if ( $instance->{'_maps'}->{$_} ) {
                $rs = $instance->{'_maps'}->{$_}->mode( 0640 );
                $ret ||= $rs;
                next if $rs;
            }

            $rs = $instance->postmap( $_ );
            $ret ||= $rs;
        }

        $? ||= $ret;
    }

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
