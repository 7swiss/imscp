=head1 NAME

 iMSCP::Packages::FrontEnd::Installer - i-MSCP FrontEnd package installer

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

package iMSCP::Packages::FrontEnd::Installer;

use strict;
use warnings;
use File::Basename;
use iMSCP::Composer;
use iMSCP::Crypt qw/ apr1MD5 randomStr /;
use iMSCP::Database;
use iMSCP::Debug qw / debug error getMessageByType /;
use iMSCP::Dialog::InputValidation qw/
    isNumber isNumberInRange isOneOfStringsInList isStringInList isStringNotInList isValidDomain isValidEmail isValidPassword isValidUsername
    /;
use iMSCP::Dir;
use iMSCP::Execute qw/ execute /;
use iMSCP::File;
use iMSCP::Getopt;
use iMSCP::OpenSSL;
use iMSCP::Net;
use iMSCP::Service;
use iMSCP::Stepper qw/ step startDetail endDetail /;
use iMSCP::SystemUser;
use iMSCP::TemplateParser qw/ getBloc processByRef replaceBlocByRef /;
use Net::LibIDN qw/ idn_to_ascii idn_to_unicode /;
use iMSCP::Packages::FrontEnd;
use iMSCP::Servers::Mta;
use iMSCP::Servers::Named;
use version;
use parent 'iMSCP::Common::Singleton';

=head1 DESCRIPTION

 i-MSCP FrontEnd package installer.

=head1 PUBLIC METHODS

=over 4

=item registerSetupListeners( )

 Register setup event listeners

 Return int 0 on success, other on failure

=cut

sub registerSetupListeners
{
    my ($self) = @_;

    my $rs = $self->{'eventManager'}->registerOne( 'beforeSetupDialog',
        sub {
            push @{$_[0]},
                sub { $self->askMasterAdminCredentials( @_ ) },
                sub { $self->askMasterAdminEmail( @_ ) },
                sub { $self->askDomain( @_ ) },
                sub { $self->askSsl( @_ ) },
                sub { $self->askHttpPorts( @_ ) },
                sub { $self->askAltUrlsFeature( @_ ) };
            0;
        }
    );
    $rs ||= $self->{'eventManager'}->registerOne( 'beforeSetupPreInstallServers',
        sub {
            eval {
                my $composer = iMSCP::Composer->new(
                    user          => $main::imscpConfig{'ROOT_USER'},
                    group         => $main::imscpConfig{'ROOT_GROUP'},
                    home_dir      => "$main::imscpConfig{'GUI_ROOT_DIR'}/data/persistent/frontend",
                    working_dir   => $main::imscpConfig{'GUI_ROOT_DIR'},
                    composer_json => ( iMSCP::File->new(
                        filename => "$main::imscpConfig{'GUI_ROOT_DIR'}/composer.json"
                    )->get() or die( getMessageByType( 'error', { amount => 1, remove => 1 } )) ),
                    composer_path => '/usr/local/bin/composer'
                );
                $composer->getComposerJson( 'scalar' )->{'config'} = {
                    %{$composer->getComposerJson( 'scalar' )->{'config'}},
                    cafile => $main::imscpConfig{'DISTRO_CA_BUNDLE'},
                    capath => $main::imscpConfig{'DISTRO_CA_PATH'}
                };
                startDetail;
                $composer->setStdRoutines( sub {}, sub {
                        ( my $stdout = $_[0] ) =~ s/^\s+|\s+$//g;
                        return if $stdout eq '';

                        step( undef, <<"EOT", 1, 1 )
Installing/Updating i-MSCP frontEnd (dependencies) composer packages ...

$stdout

Depending on your connection speed, this may take few minutes ...
EOT
                    }
                )->installPackages();
                endDetail;
            };
            if ( $@ ) {
                endDetail;
                error( $@ );
                return 1;
            }

            0;
        }
    );
}

=item askMasterAdminCredentials( \%dialog )

 Ask for master administrator credentials

 Param iMSCP::Dialog \%dialog
 Return int 0 or 30, die on failure

=cut

sub askMasterAdminCredentials
{
    my (undef, $dialog) = @_;

    my ($username, $password) = ( '', '' );
    my $db = iMSCP::Database->getInstance();

    eval { $db->useDatabase( main::setupGetQuestion( 'DATABASE_NAME' )); };
    $db = undef if $@;

    if ( iMSCP::Getopt->preseed ) {
        $username = main::setupGetQuestion( 'ADMIN_LOGIN_NAME', 'admin' );
        $password = main::setupGetQuestion( 'ADMIN_PASSWORD' );
    } elsif ( $db ) {
        my $dbh = $db->getRawDb();
        local $dbh->{'RaiseError'} = 1;
        my $row = $dbh->selectrow_hashref( "SELECT admin_name, admin_pass FROM admin WHERE created_by = 0 AND admin_type = 'admin'", );

        if ( $row ) {
            $username = $row->{'admin_name'} // '';
            $password = $row->{'admin_pass'} // '';
        }
    }

    main::setupSetQuestion( 'ADMIN_OLD_LOGIN_NAME', $username );

    $iMSCP::Dialog::InputValidation::lastValidationError = '';

    if ( isOneOfStringsInList( iMSCP::Getopt->reconfigure, [ 'admin', 'admin_credentials', 'all', 'forced' ] )
        || !isValidUsername( $username )
        || $password eq ''
    ) {
        $password = '';
        my $rs = 0;

        do {
            if ( $username eq '' ) {
                $iMSCP::Dialog::InputValidation::lastValidationError = '';
                $username = 'admin';
            }

            ( $rs, $username ) = $dialog->inputbox( <<"EOF", $username );
$iMSCP::Dialog::InputValidation::lastValidationError
Please enter a username for the master administrator (leave empty for default):
\\Z \\Zn
EOF
            if ( isValidUsername( $username ) ) {
                if ( $db ) {
                    my $dbh = $db->getRawDb();
                    local $dbh->{'RaiseError'} = 1;
                    my $row = $dbh->selectrow_hashref( 'SELECT 1 FROM admin WHERE admin_name = ? AND created_by <> 0', undef, $username );

                    if ( $row ) {
                        $iMSCP::Dialog::InputValidation::lastValidationError = <<"EOF";
\\Z1This username is not available.\\Zn
EOF
                    }
                }
            }
        } while $rs < 30
            && $iMSCP::Dialog::InputValidation::lastValidationError;

        return $rs unless $rs < 30;

        do {
            if ( $password eq '' ) {
                $iMSCP::Dialog::InputValidation::lastValidationError = '';
                $password = randomStr( 16, iMSCP::Crypt::ALNUM );
            }

            ( $rs, $password ) = $dialog->inputbox( <<"EOF", $password );
$iMSCP::Dialog::InputValidation::lastValidationError
Please enter a password for the master administrator (leave empty for autogeneration):
\\Z \\Zn
EOF
        } while $rs < 30
            && !isValidPassword( $password );

        return $rs unless $rs < 30;
    } else {
        $password = '' unless iMSCP::Getopt->preseed
    }

    main::setupSetQuestion( 'ADMIN_LOGIN_NAME', $username );
    main::setupSetQuestion( 'ADMIN_PASSWORD', $password );
    0;
}

=item askMasterAdminEmail( \%dialog )

 Ask for master administrator email address

 Param iMSCP::Dialog \%dialog
 Return int 0 or 30

=cut

sub askMasterAdminEmail
{
    my (undef, $dialog) = @_;

    my $email = main::setupGetQuestion( 'DEFAULT_ADMIN_ADDRESS' );

    $iMSCP::Dialog::InputValidation::lastValidationError = '';

    if ( isOneOfStringsInList( iMSCP::Getopt->reconfigure, [ 'admin', 'admin_email', 'all', 'forced' ] ) || !isValidEmail( $email ) ) {
        my $rs = 0;
        $iMSCP::Dialog::InputValidation::lastValidationError = '' if $email eq '';

        do {
            ( $rs, $email ) = $dialog->inputbox( <<"EOF", $email );
$iMSCP::Dialog::InputValidation::lastValidationError
Please enter an email address for the master administrator:
\\Z \\Zn
EOF
        } while $rs < 30
            && !isValidEmail( $email );

        return $rs unless $rs < 30;
    }

    main::setupSetQuestion( 'DEFAULT_ADMIN_ADDRESS', $email );
    0;
}

=item askDomain( \%dialog )

 Show for frontEnd domain name

 Param iMSCP::Dialog \%dialog
 Return int 0 or 30

=cut

sub askDomain
{
    my (undef, $dialog) = @_;

    my $domainName = main::setupGetQuestion(
        'BASE_SERVER_VHOST',
        ( iMSCP::Getopt->preseed
            ? do {
                my @labels = split /\./, main::setupGetQuestion( 'SERVER_HOSTNAME' );
                'panel.' . join( '.', @labels[1 .. $#labels] );
            }
            : ''
        )
    );

    $iMSCP::Dialog::InputValidation::lastValidationError = '';

    if ( isOneOfStringsInList( iMSCP::Getopt->reconfigure, [ 'panel', 'panel_hostname', 'hostnames', 'all', 'forced' ] )
        || !isValidDomain( $domainName )
    ) {
        if ( $domainName eq '' ) {
            $iMSCP::Dialog::InputValidation::lastValidationError = '';
            my @labels = split /\./, main::setupGetQuestion( 'SERVER_HOSTNAME' );
            $domainName = 'panel.' . join( '.', @labels[1 .. $#labels] );
        }

        $domainName = idn_to_unicode( $domainName, 'utf-8' ) // '';

        my $rs = 0;

        do {
            ( $rs, $domainName ) = $dialog->inputbox( <<"EOF", $domainName );
$iMSCP::Dialog::InputValidation::lastValidationError
Please enter a domain name for the control panel: (leave empty for autodetection)
\\Z \\Zn
EOF
        } while $rs < 30 && !isValidDomain( $domainName );

        return $rs unless $rs < 30;
    }

    main::setupSetQuestion( 'BASE_SERVER_VHOST', idn_to_ascii( $domainName, 'utf-8' ) // '' );
    0;
}

=item askSsl( \%dialog )

 Ask for frontEnd SSL certificate

 Param iMSCP::Dialog \%dialog
 Return int 0 or 30

=cut

sub askSsl
{
    my (undef, $dialog) = @_;

    my $domainName = main::setupGetQuestion( 'BASE_SERVER_VHOST' );
    my $domainNameUnicode = idn_to_unicode( $domainName, 'utf-8' ) // '';
    my $sslEnabled = main::setupGetQuestion( 'PANEL_SSL_ENABLED', iMSCP::Getopt->preseed ? 'yes' : '' );
    my $selfSignedCertificate = main::setupGetQuestion( 'PANEL_SSL_SELFSIGNED_CERTIFICATE', iMSCP::Getopt->preseed ? 'yes' : 'no' );
    my $privateKeyPath = main::setupGetQuestion( 'PANEL_SSL_PRIVATE_KEY_PATH', '/root' );
    my $passphrase = main::setupGetQuestion( 'PANEL_SSL_PRIVATE_KEY_PASSPHRASE' );
    my $certificatePath = main::setupGetQuestion( 'PANEL_SSL_CERTIFICATE_PATH', '/root' );
    my $caBundlePath = main::setupGetQuestion( 'PANEL_SSL_CA_BUNDLE_PATH', '/root' );
    my $baseServerVhostPrefix = main::setupGetQuestion( 'BASE_SERVER_VHOST_PREFIX', 'http://' );
    my $openSSL = iMSCP::OpenSSL->new();

    if ( isOneOfStringsInList( iMSCP::Getopt->reconfigure, [ 'panel', 'panel_ssl', 'ssl', 'all', 'forced' ] )
        || !isStringInList( $sslEnabled, 'yes', 'no' )
        || ( $sslEnabled eq 'yes' && isOneOfStringsInList( iMSCP::Getopt->reconfigure, [ 'panel_hostname', 'hostnames' ] ) )
    ) {
        my $rs = $dialog->yesno( <<'EOF', $sslEnabled eq 'no' ? 1 : 0 );
Do you want to enable SSL for the control panel?
EOF
        if ( $rs == 0 ) {
            $sslEnabled = 'yes';

            $rs = $dialog->yesno( <<"EOF", $selfSignedCertificate eq 'no' ? 1 : 0 );
Do you have a SSL certificate for the $domainNameUnicode domain?
EOF
            if ( $rs == 0 ) {
                my $msg = '';

                do {
                    $dialog->msgbox( <<"EOF" );
$msg
Please select your private key in next dialog.
EOF
                    do {
                        ( $rs, $privateKeyPath ) = $dialog->fselect( $privateKeyPath );
                    } while $rs < 30
                        && !( $privateKeyPath && -f $privateKeyPath );

                    return $rs unless $rs < 30;

                    ( $rs, $passphrase ) = $dialog->passwordbox( <<"EOF", $passphrase );
Please enter the passphrase for your private key if any:
\\Z \\Zn
EOF
                    return $rs unless $rs < 30;

                    $openSSL->{'private_key_container_path'} = $privateKeyPath;
                    $openSSL->{'private_key_passphrase'} = $passphrase;

                    $msg = '';
                    if ( $openSSL->validatePrivateKey() ) {
                        getMessageByType( 'error', { amount => 1, remove => 1 } );
                        $msg = <<"EOF";
\\Z1Invalid private key or passphrase.\\Zn
EOF
                    }
                } while $rs < 30 && $msg;

                return $rs unless $rs < 30;

                $rs = $dialog->yesno( <<'EOF' );
Do you have a SSL CA Bundle?
EOF
                if ( $rs == 0 ) {
                    do {
                        ( $rs, $caBundlePath ) = $dialog->fselect( $caBundlePath );
                    } while $rs < 30
                        && !( $caBundlePath && -f $caBundlePath );

                    return $rs unless $rs < 30;

                    $openSSL->{'ca_bundle_container_path'} = $caBundlePath;
                } else {
                    $openSSL->{'ca_bundle_container_path'} = '';
                }

                $dialog->msgbox( <<'EOF' );
Please select your SSL certificate in next dialog.
EOF
                $rs = 1;

                do {
                    $dialog->msgbox( <<"EOF" ) unless $rs;
\\Z1Invalid SSL certificate.\\Zn
EOF
                    do {
                        ( $rs, $certificatePath ) = $dialog->fselect( $certificatePath );
                    } while $rs < 30 && !( $certificatePath && -f $certificatePath );

                    return $rs unless $rs < 30;

                    getMessageByType( 'error', { amount => 1, remove => 1 } );
                    $openSSL->{'certificate_container_path'} = $certificatePath;
                } while $rs < 30
                    && $openSSL->validateCertificate();

                return $rs unless $rs < 30;
            } else {
                $selfSignedCertificate = 'yes';
            }

            if ( $sslEnabled eq 'yes' ) {
                my %choices = ( 'http://', 'No secure access (No SSL)', 'https://', 'Secure access (SSL)' );
                ( $rs, $baseServerVhostPrefix ) = $dialog->radiolist(
                    <<"EOF", \%choices, ( grep( $baseServerVhostPrefix eq $_, keys %choices ) )[0] || 'https://' );
Please choose the default access mode for the control panel:
\\Z \\Zn
EOF
            }
        } else {
            $sslEnabled = 'no';
        }
    } elsif ( $sslEnabled eq 'yes' && !iMSCP::Getopt->preseed ) {
        $openSSL->{'private_key_container_path'} = "$main::imscpConfig{'CONF_DIR'}/$domainName.pem";
        $openSSL->{'ca_bundle_container_path'} = "$main::imscpConfig{'CONF_DIR'}/$domainName.pem";
        $openSSL->{'certificate_container_path'} = "$main::imscpConfig{'CONF_DIR'}/$domainName.pem";

        if ( $openSSL->validateCertificateChain() ) {
            getMessageByType( 'error', { amount => 1, remove => 1 } );
            $dialog->msgbox( <<'EOF' );
Your SSL certificate for the control panel is missing or invalid.
EOF
            main::setupSetQuestion( 'PANEL_SSL_ENABLED', '' );
            goto &{askSsl};
        }

        # In case the certificate is valid, we skip SSL setup process
        main::setupSetQuestion( 'PANEL_SSL_SETUP', 'no' );
    }

    main::setupSetQuestion( 'PANEL_SSL_ENABLED', $sslEnabled );
    main::setupSetQuestion( 'PANEL_SSL_SELFSIGNED_CERTIFICATE', $selfSignedCertificate );
    main::setupSetQuestion( 'PANEL_SSL_PRIVATE_KEY_PATH', $privateKeyPath );
    main::setupSetQuestion( 'PANEL_SSL_PRIVATE_KEY_PASSPHRASE', $passphrase );
    main::setupSetQuestion( 'PANEL_SSL_CERTIFICATE_PATH', $certificatePath );
    main::setupSetQuestion( 'PANEL_SSL_CA_BUNDLE_PATH', $caBundlePath );
    main::setupSetQuestion( 'BASE_SERVER_VHOST_PREFIX', $sslEnabled eq 'yes' ? $baseServerVhostPrefix : 'http://' );
    0;
}

=item askHttpPorts( \%dialog )

 Ask for frontEnd http ports

 Param iMSCP::Dialog \%dialog
 Return int 0 or 30

=cut

sub askHttpPorts
{
    my (undef, $dialog) = @_;

    my $httpPort = main::setupGetQuestion( 'BASE_SERVER_VHOST_HTTP_PORT', iMSCP::Getopt->preseed ? 8880 : '' );
    my $httpsPort = main::setupGetQuestion( 'BASE_SERVER_VHOST_HTTPS_PORT', iMSCP::Getopt->preseed ? 8443 : '' );
    my $ssl = main::setupGetQuestion( 'PANEL_SSL_ENABLED', iMSCP::Getopt->preseed ? 'yes' : '' );

    $iMSCP::Dialog::InputValidation::lastValidationError = '';

    if ( isOneOfStringsInList( iMSCP::Getopt->reconfigure, [ 'panel', 'panel_ports', 'all', 'forced' ] )
        || !isNumber( $httpPort )
        || !isNumberInRange( $httpPort, 1025, 65535 )
    ) {
        my $rs = 0;

        do {
            if ( $httpPort eq '' ) {
                $iMSCP::Dialog::InputValidation::lastValidationError = '';
                $httpPort = 8880;
            }

            ( $rs, $httpPort ) = $dialog->inputbox( <<"EOF", $httpPort );
$iMSCP::Dialog::InputValidation::lastValidationError
Please enter the HTTP port for the control panel:
\\Z \\Zn
EOF
        } while $rs < 30 && ( !isNumber( $httpPort ) || !isNumberInRange( $httpPort, 1025, 65535 ) );

        return $rs unless $rs < 30;
    }

    main::setupSetQuestion( 'BASE_SERVER_VHOST_HTTP_PORT', $httpPort );

    if ( $ssl eq 'yes' ) {
        if ( isOneOfStringsInList( iMSCP::Getopt->reconfigure, [ 'panel', 'panel_ports', 'panel_ssl', 'ssl', 'all', 'forced' ] )
            || !isNumber( $httpsPort )
            || !isNumberInRange( $httpsPort, 1025, 65535 )
            || !isStringNotInList( $httpsPort, $httpPort )
        ) {
            my $rs = 0;

            do {
                if ( $httpsPort eq '' ) {
                    $iMSCP::Dialog::InputValidation::lastValidationError = '';
                    $httpsPort = 8443;
                }

                ( $rs, $httpsPort ) = $dialog->inputbox( <<"EOF", $httpsPort );
$iMSCP::Dialog::InputValidation::lastValidationError
Please enter the HTTPS port for the control panel:
\\Z \\Zn
EOF
            } while $rs < 30 && ( !isNumber( $httpsPort ) || !isNumberInRange( $httpsPort, 1025, 65535 ) || !isStringNotInList( $httpsPort,
                $httpPort ) );

            return $rs unless $rs < 30;
        }
    } else {
        $httpsPort = '';
    }

    main::setupSetQuestion( 'BASE_SERVER_VHOST_HTTPS_PORT', $httpsPort );
    0;
}

=item askAltUrlsFeature( \%dialog )

 Ask for alternative URL feature

 Param iMSCP::Dialog \%dialog
 Return int 0 to go on next question, 30 to go back to the previous question

=cut

sub askAltUrlsFeature
{
    my (undef, $dialog) = @_;

    my $value = main::setupGetQuestion( 'CLIENT_DOMAIN_ALT_URLS', iMSCP::Getopt->preseed ? 'yes' : '' );
    my %choices = ( 'yes', 'Yes', 'no', 'No' );

    if ( isOneOfStringsInList( iMSCP::Getopt->reconfigure, [ 'panel', 'alt_urls', 'all', 'forced' ] )
        || !isStringInList( $value, keys %choices )
    ) {
        ( my $rs, $value ) = $dialog->radiolist( <<"EOF", \%choices, ( grep( $value eq $_, keys %choices ) )[0] || 'yes' );
Do you want to enable the alternative URLs feature for client domains?

This feature allows the clients to access their websites through alternative URLs such as http://dmn1.panel.domain.tld
\\Z \\Zn
EOF
        return $rs unless $rs < 30;
    }

    main::setupSetQuestion( 'CLIENT_DOMAIN_ALT_URLS', $value );
    0;
}

=item preinstall( )

 Process preinstall tasks

 Return int 0 on success, other on failure

=cut

sub preinstall
{
    my ($self) = @_;

    $self->{'eventManager'}->registerOne(
        'afterSetupPreInstallPackages',
        sub {
            eval {
                my ($composer, $step) = ( $self->getComposer(), 0 );
                my $stdRoutine = sub {
                    ( my $stdout = $_[0] ) =~ s/^\s+|\s+$//g;
                    return if $stdout eq '';

                    step( undef, <<"EOT", 3, $step )
Installing/Updating i-MSCP frontEnd (tools) composer packages ...

$stdout

Depending on your connection speed, this may take few minutes ...
EOT
                };

                startDetail;

                if ( iMSCP::Getopt->clearPackageCache ) {
                    $step++;
                    $composer->setStdRoutines( sub {}, $stdRoutine )->clearPackageCache();
                }

                if ( iMSCP::Getopt->skipPackageUpdate ) {
                    $step++;
                    eval {
                        $composer->setStdRoutines( $stdRoutine, sub {} )->checkPackageRequirements();
                    };
                    die( "Unmet requirements. Please rerun the the installer without the '-a' option." ) if $@;
                    endDetail;
                    return;
                }

                $step++;
                $composer->setStdRoutines( sub {}, $stdRoutine )->updatePackages( undef, 'skip-autoloader' );
                undef $self->{'_composer'};
                endDetail;
            };
            if ( $@ ) {
                endDetail;
                undef $self->{'_composer'};
                error( $@ );
                return 1;
            }

            0;
        }
    );
}

=item install( )

 Process install tasks

 Return int 0 on success, other on failure

=cut

sub install
{
    my ($self) = @_;

    my $rs = $self->_setupMasterAdmin();
    $rs ||= $self->_setupSsl();
    $rs ||= $self->_setHttpdVersion();
    $rs ||= $self->_addMasterWebUser();
    $rs ||= $self->_makeDirs();
    $rs ||= $self->_copyPhpBinary();
    $rs ||= $self->_buildPhpConfig();
    $rs ||= $self->_buildHttpdConfig();
    $rs ||= $self->_deleteDnsZone();
    $rs ||= $self->_addDnsZone();
    $rs ||= $self->_installSystemFiles();
    $rs ||= $self->_cleanup();
}

=item dpkgPostInvokeTasks( )

 Process dpkg post-invoke tasks

 See #IP-1641 for further details.

 Return int 0 on success, other on failure

=cut

sub dpkgPostInvokeTasks
{
    my ($self) = @_;

    if ( -f '/usr/local/sbin/imscp_panel' ) {
        unless ( -f $self->{'config'}->{'PHP_FPM_BIN_PATH'} ) {
            # Cover case where administrator removed the package
            my $rs = $self->{'frontend'}->stop();
            $rs ||= iMSCP::File->new( filename => '/usr/local/sbin/imscp_panel' )->delFile();
            return $rs;
        }

        my $v1 = $self->_getFullPhpVersionFor( $self->{'config'}->{'PHP_FPM_BIN_PATH'} );
        my $v2 = $self->_getFullPhpVersionFor( '/usr/local/sbin/imscp_panel' );
        return 0 unless defined $v1 && defined $v2 && $v1 ne $v2; # Don't act when not necessary
        debug( sprintf( "Updating i-MSCP frontEnd PHP-FPM binary from version `%s' to version `%s'", $v2, $v1 ));
    }

    my $rs = $self->{'frontend'}->stopPhpFpm();
    $rs ||= $self->_copyPhpBinary();
    return $rs if $rs || !-f '/usr/local/etc/imscp_panel/php-fpm.conf';

    $self->{'frontend'}->startPhpFpm();
}

=item getComposer( )

 Get iMSCP::Composer instance used for FrontEnd tools installation

 Return iMSCP::Composer

=cut

sub getComposer
{
    my ($self) = @_;

    $self->{'_composer'} ||= iMSCP::Composer->new(
        user          => $main::imscpConfig{'IMSCP_USER'},
        group         => $main::imscpConfig{'IMSCP_GROUP'},
        working_dir   => "$main::imscpConfig{'IMSCP_HOMEDIR'}/packages",
        composer_path => '/usr/local/bin/composer'
    );
}

=back

=head1 PRIVATE METHODS

=over 4

=item _init( )

 Initialize instance

 Return iMSCP::Packages::FrontEnd::Installer

=cut

sub _init
{
    my ($self) = @_;

    $self->{'frontend'} = iMSCP::Packages::FrontEnd->getInstance();
    $self->{'eventManager'} = $self->{'frontend'}->{'eventManager'};
    $self->{'cfgDir'} = $self->{'frontend'}->{'cfgDir'};
    $self->{'config'} = $self->{'frontend'}->{'config'};
    $self;
}

=item _setupMasterAdmin( )

 Setup master administrator

 Return int 0 on success, other on failure

=cut

sub _setupMasterAdmin
{
    my $login = main::setupGetQuestion( 'ADMIN_LOGIN_NAME' );
    my $loginOld = main::setupGetQuestion( 'ADMIN_OLD_LOGIN_NAME' );
    my $password = main::setupGetQuestion( 'ADMIN_PASSWORD' );
    my $email = main::setupGetQuestion( 'DEFAULT_ADMIN_ADDRESS' );

    return 0 if $password eq '';

    $password = apr1MD5( $password );

    my $db = iMSCP::Database->getInstance();
    my $dbh = $db->getRawDb();

    eval {
        my $oldDbName = $db->useDatabase( main::setupGetQuestion( 'DATABASE_NAME' ));

        {
            local $dbh->{'RaiseError'} = 1;
            $dbh->begin_work();

            my $row = $dbh->selectrow_hashref( "SELECT admin_id FROM admin WHERE admin_name = ?", undef, $loginOld );

            if ( $row ) {
                $dbh->do(
                    'UPDATE admin SET admin_name = ?, admin_pass = ?, email = ? WHERE admin_id = ?',
                    undef, $login, $password, $email, $row->{'admin_id'}
                );
            } else {
                $dbh->do(
                    'INSERT INTO admin (admin_name, admin_pass, admin_type, email) VALUES (?, ?, ?, ?)', undef, $login, $password, 'admin', $email
                );
                $dbh->do( 'INSERT INTO user_gui_props SET user_id = LAST_INSERT_ID()' );
            }

            $dbh->commit();
        }

        $db->useDatabase( $oldDbName ) if $oldDbName;
    };
    if ( $@ ) {
        $dbh->rollback();
        error( $@ );
        return 1;
    }

    0
}

=item _setupSsl( )

 Setup SSL

 Return int 0 on success, other on failure

=cut

sub _setupSsl
{
    my $sslEnabled = main::setupGetQuestion( 'PANEL_SSL_ENABLED' );
    my $oldCertificate = $main::imscpOldConfig{'BASE_SERVER_VHOST'};
    my $domainName = main::setupGetQuestion( 'BASE_SERVER_VHOST' );

    # Remove old certificate if any (handle case where panel hostname has been changed)
    if ( $oldCertificate ne '' && $oldCertificate ne "$domainName.pem" && -f "$main::imscpConfig{'CONF_DIR'}/$oldCertificate" ) {
        my $rs = iMSCP::File->new( filename => "$main::imscpConfig{'CONF_DIR'}/$oldCertificate" )->delFile();
        return $rs if $rs;
    }

    if ( $sslEnabled eq 'no' || main::setupGetQuestion( 'PANEL_SSL_SETUP', 'yes' ) eq 'no' ) {
        if ( $sslEnabled eq 'no' && -f "$main::imscpConfig{'CONF_DIR'}/$domainName.pem" ) {
            my $rs = iMSCP::File->new( filename => "$main::imscpConfig{'CONF_DIR'}/$domainName.pem" )->delFile();
            return $rs if $rs;
        }

        return 0;
    }

    if ( main::setupGetQuestion( 'PANEL_SSL_SELFSIGNED_CERTIFICATE' ) eq 'yes' ) {
        return iMSCP::OpenSSL->new(
            certificate_chains_storage_dir => $main::imscpConfig{'CONF_DIR'},
            certificate_chain_name         => $domainName
        )->createSelfSignedCertificate(
            {
                common_name => $domainName,
                email       => main::setupGetQuestion( 'DEFAULT_ADMIN_ADDRESS' )
            }
        );
    }

    iMSCP::OpenSSL->new(
        certificate_chains_storage_dir => $main::imscpConfig{'CONF_DIR'},
        certificate_chain_name         => $domainName,
        private_key_container_path     => main::setupGetQuestion( 'PANEL_SSL_PRIVATE_KEY_PATH' ),
        private_key_passphrase         => main::setupGetQuestion( 'PANEL_SSL_PRIVATE_KEY_PASSPHRASE' ),
        certificate_container_path     => main::setupGetQuestion( 'PANEL_SSL_CERTIFICATE_PATH' ),
        ca_bundle_container_path       => main::setupGetQuestion( 'PANEL_SSL_CA_BUNDLE_PATH' )
    )->createCertificateChain();
}

=item _setHttpdVersion( )

 Set httpd version

 Return int 0 on success, other on failure

=cut

sub _setHttpdVersion( )
{
    my ($self) = @_;

    my $rs = execute( 'nginx -v', \ my $stdout, \ my $stderr );
    debug( $stdout ) if $stdout;
    error( $stderr || 'Unknown error' ) if $rs;
    return $rs if $rs;

    if ( $stderr !~ m%nginx/([\d.]+)% ) {
        error( "Couldn't guess Nginx version" );
        return 1;
    }

    $self->{'config'}->{'HTTPD_VERSION'} = $1;
    debug( sprintf( 'Nginx version set to: %s', $1 ));
    0;
}

=item _addMasterWebUser( )

 Add master Web user

 Return int 0 on success, other on failure

=cut

sub _addMasterWebUser
{
    my ($self) = @_;

    my $rs = eval {
        my $rs = $self->{'eventManager'}->trigger( 'beforeFrontEndAddUser' );
        return $rs if $rs;

        my $usergroup = $main::imscpConfig{'SYSTEM_USER_PREFIX'} . $main::imscpConfig{'SYSTEM_USER_MIN_UID'};

        my $db = iMSCP::Database->getInstance();
        my $dbh = $db->getRawDb();
        local $dbh->{'RaiseError'} = 1;

        $db->useDatabase( main::setupGetQuestion( 'DATABASE_NAME' ));

        my $row = $dbh->selectrow_hashref(
            "SELECT admin_sys_name, admin_sys_uid, admin_sys_gname FROM admin WHERE admin_type = 'admin' AND created_by = 0 LIMIT 1"
        );
        $row or die( "Couldn't find master administrator user in database" );

        my ($oldUser, $uid, $gid) = ( $row->{'admin_sys_uid'} && $row->{'admin_sys_uid'} ne '0' )
            ? ( getpwuid( $row->{'admin_sys_uid'} ) )[0, 2, 3] : ();

        $rs = iMSCP::SystemUser->new(
            username       => $oldUser,
            comment        => 'i-MSCP Control Panel Web User',
            home           => $main::imscpConfig{'GUI_ROOT_DIR'},
            skipCreateHome => 1
        )->addSystemUser( $usergroup, $usergroup );
        return $rs if $rs;

        ( $uid, $gid ) = ( getpwnam( $usergroup ) )[2, 3];

        $dbh->do(
            "UPDATE admin SET admin_sys_name = ?, admin_sys_uid = ?, admin_sys_gname = ?, admin_sys_gid = ? WHERE admin_type = 'admin'",
            undef, $usergroup, $uid, $usergroup, $gid
        );

        $rs = iMSCP::SystemUser->new( username => $usergroup )->addToGroup( $main::imscpConfig{'IMSCP_GROUP'} );
        $rs = iMSCP::SystemUser->new( username => $usergroup )->addToGroup( iMSCP::Servers::Mta->factory()->{'config'}->{'MTA_MAILBOX_GID_NAME'} );
        $rs ||= iMSCP::SystemUser->new( username => $self->{'config'}->{'HTTPD_USER'} )->addToGroup( $usergroup );
        $rs ||= $self->{'eventManager'}->trigger( 'afterFrontEndAddUser' );
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    $rs;
}

=item _makeDirs( )

 Create directories

 Return int 0 on success, other on failure

=cut

sub _makeDirs
{
    my ($self) = @_;

    my $rs = $self->{'eventManager'}->trigger( 'beforeFrontEndMakeDirs' );
    return $rs if $rs;

    my $rootUName = $main::imscpConfig{'ROOT_USER'};
    my $rootGName = $main::imscpConfig{'ROOT_GROUP'};

    my $nginxTmpDir = $self->{'config'}->{'HTTPD_CACHE_DIR_DEBIAN'};
    $nginxTmpDir = $self->{'config'}->{'HTTPD_CACHE_DIR_NGINX'} unless -d $nginxTmpDir;

    eval {
        # Force re-creation of cache directory tree (needed to prevent any permissions problem from an old installation)
        # See #IP-1530
        iMSCP::Dir->new( dirname => $nginxTmpDir )->remove();

        for ( [ $nginxTmpDir, $rootUName, $rootGName, 0755 ],
            [ $self->{'config'}->{'HTTPD_CONF_DIR'}, $rootUName, $rootGName, 0755 ],
            [ $self->{'config'}->{'HTTPD_LOG_DIR'}, $rootUName, $rootGName, 0755 ],
            [ $self->{'config'}->{'HTTPD_SITES_AVAILABLE_DIR'}, $rootUName, $rootGName, 0755 ],
            [ $self->{'config'}->{'HTTPD_SITES_ENABLED_DIR'}, $rootUName, $rootGName, 0755 ]
        ) {
            iMSCP::Dir->new( dirname => $_->[0] )->make( {
                user  => $_->[1],
                group => $_->[2],
                mode  => $_->[3]
            } );
        }

        if ( iMSCP::Service->getInstance->isSystemd() ) {
            iMSCP::Dir->new( dirname => '/run/imscp' )->make( {
                user  => $self->{'config'}->{'HTTPD_USER'},
                group => $self->{'config'}->{'HTTPD_GROUP'},
                mode  => 0755
            } );
        }
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    $self->{'eventManager'}->trigger( 'afterFrontEndMakeDirs' );
}

=item _copyPhpBinary( )

 Copy system PHP-FPM binary for imscp_panel service

 Return int 0 on success, other on failure

=cut

sub _copyPhpBinary
{
    my ($self) = @_;

    if ( $self->{'config'}->{'PHP_FPM_BIN_PATH'} eq '' ) {
        error( "PHP `PHP_FPM_BIN_PATH' configuration parameter is not set." );
        return 1;
    }

    iMSCP::File->new( filename => $self->{'config'}->{'PHP_FPM_BIN_PATH'} )->copyFile( '/usr/local/sbin/imscp_panel' );
}

=item _buildPhpConfig( )

 Build PHP configuration

 Return int 0 on success, other on failure

=cut

sub _buildPhpConfig
{
    my ($self) = @_;

    my $rs = $self->{'eventManager'}->trigger( 'beforeFrontEndBuildPhpConfig' );
    return $rs if $rs;

    my $usergroup = $main::imscpConfig{'SYSTEM_USER_PREFIX'} . $main::imscpConfig{'SYSTEM_USER_MIN_UID'};

    $rs = $self->{'frontend'}->buildConfFile( "$self->{'cfgDir'}/php-fpm.conf",
        {
            # FPM configuration
            PHP_FPM_LOG_LEVEL                   => $self->{'config'}->{'PHP_FPM_LOG_LEVEL'},
            PHP_FPM_EMERGENCY_RESTART_THRESHOLD => $self->{'config'}->{'PHP_FPM_EMERGENCY_RESTART_THRESHOLD'},
            PHP_FPM_EMERGENCY_RESTART_INTERVAL  => $self->{'config'}->{'PHP_FPM_EMERGENCY_RESTART_INTERVAL'},
            PHP_FPM_PROCESS_CONTROL_TIMEOUT     => $self->{'config'}->{'PHP_FPM_PROCESS_CONTROL_TIMEOUT'},
            PHP_FPM_PROCESS_MAX                 => $self->{'config'}->{'PHP_FPM_PROCESS_MAX'},
            PHP_FPM_RLIMIT_FILES                => $self->{'config'}->{'PHP_FPM_RLIMIT_FILES'},
            # FPM imscp_panel pool configuration
            USER                                => $usergroup,
            GROUP                               => $usergroup,
            PHP_FPM_PROCESS_MANAGER_MODE        => $self->{'config'}->{'PHP_FPM_PROCESS_MANAGER_MODE'},
            PHP_FPM_MAX_CHILDREN                => $self->{'config'}->{'PHP_FPM_MAX_CHILDREN'},
            PHP_FPM_START_SERVERS               => $self->{'config'}->{'PHP_FPM_START_SERVERS'},
            PHP_FPM_MIN_SPARE_SERVERS           => $self->{'config'}->{'PHP_FPM_MIN_SPARE_SERVERS'},
            PHP_FPM_MAX_SPARE_SERVERS           => $self->{'config'}->{'PHP_FPM_MAX_SPARE_SERVERS'},
            PHP_FPM_PROCESS_IDLE_TIMEOUT        => $self->{'config'}->{'PHP_FPM_PROCESS_IDLE_TIMEOUT'},
            PHP_FPM_MAX_REQUESTS                => $self->{'config'}->{'PHP_FPM_MAX_REQUESTS'},
            PHP_FPM_PROCESS_MANAGER_MODE        => $self->{'config'}->{'PHP_FPM_PROCESS_MANAGER_MODE'},
            CHKROOTKIT_LOG                      => $main::imscpConfig{'CHKROOTKIT_LOG'},
            CONF_DIR                            => $main::imscpConfig{'CONF_DIR'},
            DOMAIN                              => main::setupGetQuestion( 'BASE_SERVER_VHOST' ),
            DISTRO_OPENSSL_CNF                  => $main::imscpConfig{'DISTRO_OPENSSL_CNF'},
            DISTRO_CA_BUNDLE                    => $main::imscpConfig{'DISTRO_CA_BUNDLE'},
            HOME_DIR                            => $main::imscpConfig{'GUI_ROOT_DIR'},
            MTA_VIRTUAL_MAIL_DIR                => iMSCP::Servers::Mta->factory()->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'},
            OTHER_ROOTKIT_LOG                   => $main::imscpConfig{'OTHER_ROOTKIT_LOG'} ne '' ? ":$main::imscpConfig{'OTHER_ROOTKIT_LOG'}" : '',
            RKHUNTER_LOG                        => $main::imscpConfig{'RKHUNTER_LOG'},
            TIMEZONE                            => main::setupGetQuestion( 'TIMEZONE' ),
            WEB_DIR                             => $main::imscpConfig{'GUI_ROOT_DIR'}
        },
        {
            destination => "/usr/local/etc/imscp_panel/php-fpm.conf",
            user        => $main::imscpConfig{'ROOT_USER'},
            group       => $main::imscpConfig{'ROOT_GROUP'},
            mode        => 0640
        }
    );
    $rs ||= $self->{'frontend'}->buildConfFile( "$self->{'cfgDir'}/php.ini",
        {
            PHP_OPCODE_CACHE_ENABLED    => $self->{'config'}->{'PHP_OPCODE_CACHE_ENABLED'},
            PHP_OPCODE_CACHE_MAX_MEMORY => $self->{'config'}->{'PHP_OPCODE_CACHE_MAX_MEMORY'},
            PHP_APCU_CACHE_ENABLED      => $self->{'config'}->{'PHP_APCU_CACHE_ENABLED'},
            PHP_APCU_CACHE_MAX_MEMORY   => $self->{'config'}->{'PHP_APCU_CACHE_MAX_MEMORY'},
            TIMEZONE                    => main::setupGetQuestion( 'TIMEZONE' )
        },
        {
            destination => "/usr/local/etc/imscp_panel/php.ini",
            user        => $main::imscpConfig{'ROOT_USER'},
            group       => $main::imscpConfig{'ROOT_GROUP'},
            mode        => 0640
        }
    );
    $rs ||= $self->{'eventManager'}->trigger( 'afterFrontEndBuildPhpConfig' );
}

=item _buildHttpdConfig( )

 Build httpd configuration

 Return int 0 on success, other on failure

=cut

sub _buildHttpdConfig
{
    my ($self) = @_;

    my $rs = $self->{'eventManager'}->trigger( 'beforeFrontEndBuildHttpdConfig' );
    return $rs if $rs;

    my $availableCPUcores = $self->_getNbCPUcores();
    my $nbCPUcores = $self->{'config'}->{'HTTPD_WORKER_PROCESSES'};
    $nbCPUcores = $availableCPUcores if $self->{'config'}->{'HTTPD_WORKER_PROCESSES'} eq 'auto' || $nbCPUcores > $availableCPUcores;
    $nbCPUcores = $self->{'config'}->{'HTTPD_WORKER_PROCESSES_LIMIT'} if $nbCPUcores > $self->{'config'}->{'HTTPD_WORKER_PROCESSES_LIMIT'};


    # Build main nginx configuration file
    $rs = $self->{'frontend'}->buildConfFile( "$self->{'cfgDir'}/nginx.nginx",
        {
            HTTPD_USER               => $self->{'config'}->{'HTTPD_USER'},
            HTTPD_WORKER_PROCESSES   => $nbCPUcores,
            HTTPD_WORKER_CONNECTIONS => $self->{'config'}->{'HTTPD_WORKER_CONNECTIONS'},
            HTTPD_RLIMIT_NOFILE      => $self->{'config'}->{'HTTPD_RLIMIT_NOFILE'},
            HTTPD_LOG_DIR            => $self->{'config'}->{'HTTPD_LOG_DIR'},
            HTTPD_PID_FILE           => $self->{'config'}->{'HTTPD_PID_FILE'},
            HTTPD_CONF_DIR           => $self->{'config'}->{'HTTPD_CONF_DIR'},
            HTTPD_LOG_DIR            => $self->{'config'}->{'HTTPD_LOG_DIR'},
            HTTPD_SITES_ENABLED_DIR  => $self->{'config'}->{'HTTPD_SITES_ENABLED_DIR'}
        },
        {
            destination => "$self->{'config'}->{'HTTPD_CONF_DIR'}/nginx.conf",
            user        => $main::imscpConfig{'ROOT_USER'},
            group       => $main::imscpConfig{'ROOT_GROUP'},
            mode        => 0644
        }
    );

    # Build FastCGI configuration file
    $rs = $self->{'frontend'}->buildConfFile( "$self->{'cfgDir'}/imscp_fastcgi.nginx",
        { APPLICATION_ENV => $self->{'config'}->{'APPLICATION_ENV'} },
        {
            destination => "$self->{'config'}->{'HTTPD_CONF_DIR'}/imscp_fastcgi.conf",
            user        => $main::imscpConfig{'ROOT_USER'},
            group       => $main::imscpConfig{'ROOT_GROUP'},
            mode        => 0644
        }
    );

    # Build PHP backend configuration file
    $rs = $self->{'frontend'}->buildConfFile( "$self->{'cfgDir'}/imscp_php.nginx",
        {},
        {
            destination => "$self->{'config'}->{'HTTPD_CONF_DIR'}/conf.d/imscp_php.conf",
            user        => $main::imscpConfig{'ROOT_USER'},
            group       => $main::imscpConfig{'ROOT_GROUP'},
            mode        => 0644
        }
    );
    $rs ||= $self->{'eventManager'}->trigger( 'afterFrontEndBuildHttpdConfig' );
    $rs ||= $self->{'eventManager'}->trigger( 'beforeFrontEndBuildHttpdVhosts' );
    return $rs if $rs;

    # Build frontEnd site files
    my $baseServerIpVersion = iMSCP::Net->getInstance()->getAddrVersion( main::setupGetQuestion( 'BASE_SERVER_IP' ));
    my $httpsPort = main::setupGetQuestion( 'BASE_SERVER_VHOST_HTTPS_PORT' );
    my $tplVars = {
        BASE_SERVER_VHOST            => main::setupGetQuestion( 'BASE_SERVER_VHOST' ),
        BASE_SERVER_IP               => ( $baseServerIpVersion eq 'ipv4' )
            ? main::setupGetQuestion( 'BASE_SERVER_IP' ) =~ s/^\Q0.0.0.0\E$/*/r : '[' . main::setupGetQuestion( 'BASE_SERVER_IP' ) . ']',
        BASE_SERVER_VHOST_HTTP_PORT  => main::setupGetQuestion( 'BASE_SERVER_VHOST_HTTP_PORT' ),
        BASE_SERVER_VHOST_HTTPS_PORT => $httpsPort,
        WEB_DIR                      => $main::imscpConfig{'GUI_ROOT_DIR'},
        CONF_DIR                     => $main::imscpConfig{'CONF_DIR'},
        PLUGINS_DIR                  => $main::imscpConfig{'PLUGINS_DIR'}
    };

    $rs = $self->{'frontend'}->disableSites( 'default', '00_master.conf', '00_master_ssl.conf' );
    $rs ||= $self->{'eventManager'}->register(
        'beforeFrontEndBuildConf',
        sub {
            my ($cfgTpl, $tplName) = @_;

            return 0 unless grep($_ eq $tplName, '00_master.nginx', '00_master_ssl.nginx');

            if ( $baseServerIpVersion eq 'ipv6' || main::setupGetQuestion( 'IPV6_SUPPORT' ) eq 'no' ) {
                replaceBlocByRef( '# SECTION IPv6 BEGIN.', '# SECTION IPv6 END.', '', $cfgTpl );
            }

            return 0 unless $tplName eq '00_master.nginx';

            if ( main::setupGetQuestion( 'BASE_SERVER_VHOST_PREFIX' ) eq 'https://' ) {
                replaceBlocByRef( "# SECTION http BEGIN.\n", "# SECTION http END.", '', $cfgTpl );
                return 0;
            }

            replaceBlocByRef( "# SECTION https redirect BEGIN.\n", "# SECTION https redirect END.", '', $cfgTpl );
            0;
        }
    );
    $rs ||= $self->{'frontend'}->buildConfFile( '00_master.nginx', $tplVars,
        {
            destination => "$self->{'config'}->{'HTTPD_SITES_AVAILABLE_DIR'}/00_master.conf",
            user        => $main::imscpConfig{'ROOT_USER'},
            group       => $main::imscpConfig{'ROOT_GROUP'},
            mode        => 0644
        }
    );
    $rs ||= $self->{'frontend'}->enableSites( '00_master.conf' );
    return $rs if $rs;

    if ( main::setupGetQuestion( 'PANEL_SSL_ENABLED' ) eq 'yes' ) {
        $rs ||= $self->{'frontend'}->buildConfFile( '00_master_ssl.nginx', $tplVars,
            {
                destination => "$self->{'config'}->{'HTTPD_SITES_AVAILABLE_DIR'}/00_master_ssl.conf",
                user        => $main::imscpConfig{'ROOT_USER'},
                group       => $main::imscpConfig{'ROOT_GROUP'},
                mode        => 0644
            }
        );
        $rs ||= $self->{'frontend'}->enableSites( '00_master_ssl.conf' );
        return $rs if $rs;
    } elsif ( -f "$self->{'config'}->{'HTTPD_SITES_AVAILABLE_DIR'}/00_master_ssl.conf" ) {
        $rs = iMSCP::File->new( filename => "$self->{'config'}->{'HTTPD_SITES_AVAILABLE_DIR'}/00_master_ssl.conf" )->delFile();
        return $rs if $rs;
    }

    if ( -f "$self->{'config'}->{'HTTPD_CONF_DIR'}/conf.d/default.conf" ) {
        # Nginx package as provided by Nginx Team
        $rs = iMSCP::File->new( filename => "$self->{'config'}->{'HTTPD_CONF_DIR'}/conf.d/default.conf" )->moveFile(
            "$self->{'config'}->{'HTTPD_CONF_DIR'}/conf.d/default.conf.disabled"
        );
        return $rs if $rs;
    }

    $self->{'eventManager'}->trigger( 'afterFrontEndBuildHttpdVhosts' );
}

=item _addDnsZone( )

 Add DNS zone

 Return int 0 on success, other on failure

=cut

sub _addDnsZone
{
    my ($self) = @_;

    my $rs = $self->{'eventManager'}->trigger( 'beforeNamedAddMasterZone' );
    $rs ||= iMSCP::Servers::Named->factory()->addDomain( {
        BASE_SERVER_VHOST     => main::setupGetQuestion( 'BASE_SERVER_VHOST' ),
        BASE_SERVER_IP        => main::setupGetQuestion( 'BASE_SERVER_IP' ),
        BASE_SERVER_PUBLIC_IP => main::setupGetQuestion( 'BASE_SERVER_PUBLIC_IP' ),
        DOMAIN_TYPE           => 'dmn', # (since 1.6.0)
        PARENT_DOMAIN_NAME    => main::setupGetQuestion( 'BASE_SERVER_VHOST' ), # (since 1.6.0)
        DOMAIN_NAME           => main::setupGetQuestion( 'BASE_SERVER_VHOST' ),
        DOMAIN_IP             => main::setupGetQuestion( 'BASE_SERVER_IP' ),
        MAIL_ENABLED          => 1,
        STATUS                => 'toadd' # (since 1.6.0)
    } );
    $rs ||= $self->{'eventManager'}->trigger( 'afterNamedAddMasterZone' );
}

=item _deleteDnsZone( )

 Delete previous DNS zone if needed (i.e. case where BASER_SERVER_VHOST has been modified)

 Return int 0 on success, other on failure

=cut

sub _deleteDnsZone
{
    my ($self) = @_;

    return 0 unless $main::imscpOldConfig{'BASE_SERVER_VHOST'}
        && $main::imscpOldConfig{'BASE_SERVER_VHOST'} ne main::setupGetQuestion( 'BASE_SERVER_VHOST' );

    my $rs = $self->{'eventManager'}->trigger( 'beforeNamedDeleteMasterZone' );
    $rs ||= iMSCP::Servers::Named->factory()->deleteDomain( {
        DOMAIN_NAME    => $main::imscpOldConfig{'BASE_SERVER_VHOST'},
        FORCE_DELETION => 1
    } );
    $rs ||= $self->{'eventManager'}->trigger( 'afterNamedDeleteMasterZone' );
}

=item _installSystemFiles()

 Install system files

 Return int 0 on success, 1 on failure

=cut

sub _installSystemFiles
{
    my ($self) = @_;

    eval {
        my $usergroup = $main::imscpConfig{'SYSTEM_USER_PREFIX'} . $main::imscpConfig{'SYSTEM_USER_MIN_UID'};

        for ( 'cron.daily', 'logrotate.d' ) {
            my $fileContent = iMSCP::File->new( filename => "$self->{'cfgDir'}/$_/imscp_frontend" )->get();
            defined $fileContent or die( sprintf( "Couldn't read the %s file", "$self->{'cfgDir'}/$_/imscp_frontend.conf" ));

            processByRef(
                {
                    WEB_DIR     => $main::imscpConfig{'GUI_ROOT_DIR'},
                    PANEL_USER  => $usergroup,
                    PANEL_GROUP => $usergroup
                },
                \$fileContent
            );

            my $file = iMSCP::File->new( filename => "/etc/$_/imscp_frontend" );
            my $rs = $file->set( $fileContent );
            $rs ||= $file->save();
            $rs == 0 or die( getMessageByType( 'error', { amount => 1, remove => 1 } ));
        }
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=item _cleanup( )

 Process cleanup tasks

 Return int 0 on success, other on failure

=cut

sub _cleanup
{
    my ($self) = @_;

    return 0 unless -f "$self->{'cfgDir'}/frontend.old.data";

    iMSCP::File->new( filename => "$self->{'cfgDir'}/frontend.old.data" )->delFile();
}

=item _getFullPhpVersionFor( $binaryPath )

 Get full PHP version for the given PHP binary

 Param string $binaryPath Path to PHP binary
 Return int 0 on success, other on failure

=cut

sub _getFullPhpVersionFor
{
    my (undef, $binaryPath) = @_;

    my $rs = execute( [ $binaryPath, '-nv' ], \ my $stdout, \ my $stderr );
    error( $stderr || 'Unknown error' ) if $rs;
    return undef unless $stdout;
    $stdout =~ /PHP\s+([^\s]+)/;
    $1;
}

=item _getNbCPUcores( )

 Get number of available CPU cores

 Return int Number of CPU cores

=cut

sub _getNbCPUcores
{
    execute( 'grep processor /proc/cpuinfo 2>/dev/null | wc -l', \ my $stdout );
    $stdout =~ /^(\d+)/;
    $1 || 1;
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
