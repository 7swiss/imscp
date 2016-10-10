=head1 NAME

 Modules::Alias - i-MSCP domain alias module

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2016 by internet Multi Server Control Panel
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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

package Modules::Alias;

use strict;
use warnings;
use File::Spec;
use iMSCP::Database;
use iMSCP::Debug;
use iMSCP::Dir;
use iMSCP::Execute;
use iMSCP::OpenSSL;
use Net::LibIDN qw/idn_to_unicode/;
use Servers::httpd;
use parent 'Modules::Abstract';

=head1 DESCRIPTION

 i-MSCP domain alias module.

=head1 PUBLIC METHODS

=over 4

=item getType()

 Get module type

 Return string Module type

=cut

sub getType
{
    'Dmn';
}

=item process($aliasId)

 Process module

 Param int $aliasId Domain alias unique identifier
 Return int 0 on success, other on failure

=cut

sub process
{
    my ($self, $aliasId) = @_;

    my $rs = $self->_loadData( $aliasId );
    return $rs if $rs;

    my @sql;
    if ($self->{'alias_status'} =~ /^to(?:add|change|enable)$/) {
        $rs = $self->add();
        @sql = (
            "UPDATE domain_aliasses SET alias_status = ? WHERE alias_id = ?",
            ($rs ? scalar getMessageByType( 'error' ) || 'Unknown error' : 'ok'), $aliasId
        );
    } elsif ($self->{'alias_status'} eq 'todelete') {
        $rs = $self->delete();
        if ($rs) {
            @sql = (
                "UPDATE domain_aliasses SET alias_status = ? WHERE alias_id = ?",
                scalar getMessageByType( 'error' ) || 'Unknown error', $aliasId
            );
        } else {
            @sql = ("DELETE FROM domain_aliasses WHERE alias_id = ?", $aliasId);
        }
    } elsif ($self->{'alias_status'} eq 'todisable') {
        $rs = $self->disable();
        @sql = (
            "UPDATE domain_aliasses SET alias_status = ? WHERE alias_id = ?",
            ($rs ? scalar getMessageByType( 'error' ) || 'Unknown error' : 'disabled'), $aliasId
        );
    } elsif ($self->{'alias_status'} eq 'torestore') {
        $rs = $self->restore();
        @sql = (
            "UPDATE domain_aliasses SET alias_status = ? WHERE alias_id = ?",
            ($rs ? scalar getMessageByType( 'error' ) || 'Unknown error' : 'ok'), $aliasId
        );
    }

    my $rdata = iMSCP::Database->factory()->doQuery( 'dummy', @sql );
    unless (ref $rdata eq 'HASH') {
        error( $rdata );
        return 1;
    }

    $rs;
}

=item add()

 Add domain alias

 Return int 0 on success, other on failure

=cut

sub add
{
    my $self = shift;

    if ($self->{'alias_status'} eq 'tochange') {
        my $db = iMSCP::Database->factory();

        # Sets the status of any subdomain that belongs to this domain alias to 'tochange'.
        # FIXME: This reflect a bad implementation in the way that entities are managed. This will be solved
        # in version 2.0.0.
        my $rs = $db->doQuery(
            'u',
            "
                UPDATE subdomain_alias SET subdomain_alias_status = 'tochange'
                WHERE alias_id = ? AND subdomain_alias_status <> 'todelete'
            ",
            $self->{'alias_id'}
        );
        unless (ref $rs eq 'HASH') {
            error( $rs );
            return 1;
        }

        $rs = $db->doQuery(
            'u',
            "
                UPDATE domain_dns SET domain_dns_status = 'tochange'
                WHERE alias_id = ? AND domain_dns_status NOT IN ('todelete', 'todisable', 'disabled')
            ",
            $self->{'alias_id'}
        );
        unless (ref $rs eq 'HASH') {
            error( $rs );
            return 1;
        }
    }

    $self->SUPER::add();
}

=item disable()

 Disable domain alias

 Return int 0 on success, other on failure

=cut

sub disable
{
    my $self = shift;

    # Sets the status of any subdomain that belongs to this domain alias to 'todisable'.
    my $rs = iMSCP::Database->factory()->doQuery(
        'u',
        "
            UPDATE subdomain_alias SET subdomain_alias_status = 'todisable'
            WHERE alias_id = ? AND subdomain_alias_status <> 'todelete'
        ",
        $self->{'alias_id'}
    );
    unless (ref $rs eq 'HASH') {
        error( $rs );
        return 1;
    }

    $self->SUPER::disable();
}

=back

=head1 PRIVATE METHODS

=over 4

=item _loadData($aliasId)

 Load data

 Param int $aliasId Domain Alias unique identifier
 Return int 0 on success, other on failure

=cut

sub _loadData
{
    my ($self, $aliasId) = @_;

    my $rdata = iMSCP::Database->factory()->doQuery(
        'alias_id',
        "
            SELECT t1.*, t2.domain_name AS user_home, t2.domain_admin_id, t2.domain_php, t2.domain_cgi,
                t2.domain_traffic_limit, t2.domain_mailacc_limit, t2.domain_dns, t2.web_folder_protection, t3.ip_number,
                t4.mail_on_domain
            FROM domain_aliasses AS t1
            INNER JOIN domain AS t2 ON (t1.domain_id = t2.domain_id)
            INNER JOIN server_ips AS t3 ON (t1.alias_ip_id = t3.ip_id)
            LEFT JOIN(
                SELECT sub_id, COUNT(sub_id) AS mail_on_domain FROM mail_users WHERE mail_type LIKE 'alias\\_%' GROUP BY sub_id
            ) AS t4 ON (t1.alias_id = t4.sub_id)
            WHERE t1.alias_id = ?
        ",
        $aliasId
    );
    unless (ref $rdata eq 'HASH') {
        error( $rdata );
        return 1;
    }

    unless ($rdata->{$aliasId}) {
        error( sprintf( 'Domain alias with ID %s has not been found or is in an inconsistent state', $aliasId ) );
        return 1;
    }

    %{$self} = (%{$self}, %{$rdata->{$aliasId}});
    0;
}

=item _getHttpdData($action)

 Data provider method for Httpd servers

 Param string $action Action
 Return hashref Reference to a hash containing data, die on failure

=cut

sub _getHttpdData
{
    my ($self, $action) = @_;

    $self->{'_httpd'} = do {
        my $httpd = Servers::httpd->factory();
        my $groupName = my $userName = $main::imscpConfig{'SYSTEM_USER_PREFIX'}.
            ($main::imscpConfig{'SYSTEM_USER_MIN_UID'} + $self->{'domain_admin_id'});
        my $homeDir = File::Spec->canonpath( "$main::imscpConfig{'USER_WEB_DIR'}/$self->{'user_home'}" );
        my $webDir = File::Spec->canonpath( "$homeDir/$self->{'alias_mount'}" );
        my $documentRoot = File::Spec->canonpath( "$webDir/$self->{'alias_document_root'}" );
        my $db = iMSCP::Database->factory();
        my $confLevel = $httpd->{'phpConfig'}->{'PHP_CONFIG_LEVEL'} eq 'per_user' ? 'dmn' : 'als';

        my $phpiniMatchId = $confLevel eq 'dmn' ? $self->{'domain_id'} : $self->{'alias_id'};
        my $phpini = $db->doQuery(
            'domain_id', 'SELECT * FROM php_ini WHERE domain_id = ? AND domain_type = ?', $phpiniMatchId, $confLevel
        );
        ref $phpini eq 'HASH' or die( $phpini );

        my $certData = $db->doQuery(
            'domain_id', 'SELECT * FROM ssl_certs WHERE domain_id = ? AND domain_type = ? AND status = ?',
            $self->{'alias_id'}, 'als', 'ok'
        );
        ref $certData eq 'HASH' or die( $certData );

        my $haveCert = ($certData->{$self->{'alias_id'}} && $self->isValidCertificate( $self->{'alias_name'} ));
        my $allowHSTS = ($haveCert && $certData->{$self->{'alias_id'}}->{'allow_hsts'} eq 'on');
        my $hstsMaxAge = $allowHSTS ? $certData->{$self->{'alias_id'}}->{'hsts_max_age'} : '';
        my $hstsIncludeSubDomains = ($allowHSTS && $certData->{$self->{'alias_id'}}->{'hsts_include_subdomains'} eq 'on')
            ? '; includeSubDomains' : '';

        {
            BASE_SERVER_VHOST       => $main::imscpConfig{'BASE_SERVER_VHOST'},
            BASE_SERVER_IP          => $main::imscpConfig{'BASE_SERVER_IP'},
            DOMAIN_ADMIN_ID         => $self->{'domain_admin_id'},
            DOMAIN_NAME             => $self->{'alias_name'},
            DOMAIN_NAME_UNICODE     => idn_to_unicode( $self->{'alias_name'}, 'utf-8' ),
            DOMAIN_IP               => $self->{'ip_number'},
            DOMAIN_TYPE             => 'als',
            PARENT_DOMAIN_NAME      => $self->{'alias_name'},
            ROOT_DOMAIN_NAME        => $self->{'user_home'},
            HOME_DIR                => $homeDir,
            WEB_DIR                 => $webDir,
            MOUNT_POINT             => $self->{'alias_mount'},
            DOCUMENT_ROOT           => $documentRoot,
            SHARED_MOUNT_POINT      => $self->_sharedMountPoint(),
            PEAR_DIR                => $httpd->{'phpConfig'}->{'PHP_PEAR_DIR'},
            TIMEZONE                => $main::imscpConfig{'TIMEZONE'},
            USER                    => $userName,
            GROUP                   => $groupName,
            PHP_SUPPORT             => $self->{'domain_php'},
            CGI_SUPPORT             => $self->{'domain_cgi'},
            WEB_FOLDER_PROTECTION   => $self->{'web_folder_protection'},
            SSL_SUPPORT             => $haveCert,
            HSTS_SUPPORT            => $allowHSTS,
            HSTS_MAX_AGE            => $hstsMaxAge,
            HSTS_INCLUDE_SUBDOMAINS => $hstsIncludeSubDomains,
            BWLIMIT                 => $self->{'domain_traffic_limit'},
            ALIAS                   => $userName.'als'.$self->{'alias_id'},
            FORWARD                 => $self->{'url_forward'} || 'no',
            FORWARD_TYPE            => $self->{'type_forward'} || '',
            FORWARD_PRESERVE_HOST   => $self->{'host_forward'} || 'Off',
            DISABLE_FUNCTIONS       => $phpini->{$phpiniMatchId}->{'disable_functions'} //
                'exec,passthru,phpinfo,popen,proc_open,show_source,shell,shell_exec,symlink,system',
            MAX_EXECUTION_TIME      => $phpini->{$phpiniMatchId}->{'max_execution_time'} // 30,
            MAX_INPUT_TIME          => $phpini->{$phpiniMatchId}->{'max_input_time'} // 60,
            MEMORY_LIMIT            => $phpini->{$phpiniMatchId}->{'memory_limit'} // 128,
            ERROR_REPORTING         =>
            $phpini->{$phpiniMatchId}->{'error_reporting'} || 'E_ALL & ~E_DEPRECATED & ~E_STRICT',
            DISPLAY_ERRORS          => $phpini->{$phpiniMatchId}->{'display_errors'} || 'off',
            POST_MAX_SIZE           => $phpini->{$phpiniMatchId}->{'post_max_size'} // 8,
            UPLOAD_MAX_FILESIZE     => $phpini->{$phpiniMatchId}->{'upload_max_filesize'} // 2,
            ALLOW_URL_FOPEN         => $phpini->{$phpiniMatchId}->{'allow_url_fopen'} || 'off',
            PHP_FPM_LISTEN_PORT     => ($phpini->{$phpiniMatchId}->{'id'} // 0) - 1
        }
    } unless %{$self->{'_httpd'}};

    $self->{'_httpd'};
}

=item _getMtaData($action)

 Data provider method for MTA servers

 Param string $action Action
 Return hashref Reference to a hash containing data

=cut

sub _getMtaData
{
    my ($self, $action) = @_;

    $self->{'_mta'} = do {
        {
            DOMAIN_ADMIN_ID => $self->{'domain_admin_id'},
            DOMAIN_NAME     => $self->{'alias_name'},
            DOMAIN_TYPE     => $self->getType(),
            EXTERNAL_MAIL   => $self->{'external_mail'},
            MAIL_ENABLED    => (
                $self->{'external_mail'} eq 'off' && ($self->{'mail_on_domain'} || $self->{'domain_mailacc_limit'} >= 0)
            )
        }
    } unless %{$self->{'_mta'}};

    $self->{'_mta'};
}

=item _getNamedData($action)

 Data provider method for named servers

 Param string $action Action
 Return hashref Reference to a hash containing data

=cut

sub _getNamedData
{
    my ($self, $action) = @_;

    $self->{'_named'} = do {
        my $userName = $main::imscpConfig{'SYSTEM_USER_PREFIX'}.
            ($main::imscpConfig{'SYSTEM_USER_MIN_UID'} + $self->{'domain_admin_id'});
        {
            BASE_SERVER_VHOST     => $main::imscpConfig{'BASE_SERVER_VHOST'},
            BASE_SERVER_IP        => $main::imscpConfig{'BASE_SERVER_IP'},
            BASE_SERVER_PUBLIC_IP => $main::imscpConfig{'BASE_SERVER_PUBLIC_IP'},
            DOMAIN_ADMIN_ID       => $self->{'domain_admin_id'},
            DOMAIN_NAME           => $self->{'alias_name'},
            DOMAIN_IP             => $self->{'ip_number'},
            USER_NAME             => $userName.'als'.$self->{'alias_id'},
            MAIL_ENABLED          => (
                $self->{'external_mail'} eq 'off' && ($self->{'mail_on_domain'} || $self->{'domain_mailacc_limit'} >= 0)
            )
        }
    } unless %{$self->{'_named'}};

    $self->{'_named'};
}

=item _getPackagesData($action)

 Data provider method for i-MSCP packages

 Param string $action Action
 Return hashref Reference to a hash containing data

=cut

sub _getPackagesData
{
    my ($self, $action) = @_;

    $self->{'_packages'} = do {
        my $userName = my $groupName = $main::imscpConfig{'SYSTEM_USER_PREFIX'}.
            ($main::imscpConfig{'SYSTEM_USER_MIN_UID'} + $self->{'domain_admin_id'});
        my $homeDir = File::Spec->canonpath( "$main::imscpConfig{'USER_WEB_DIR'}/$self->{'user_home'}" );
        my $webDir = File::Spec->canonpath( "$homeDir/$self->{'user_home'}/$self->{'alias_mount'}" );

        {
            DOMAIN_ADMIN_ID       => $self->{'domain_admin_id'},
            ALIAS                 => $userName,
            DOMAIN_NAME           => $self->{'alias_name'},
            ROOT_DOMAIN_NAME      => $self->{'user_home'},
            USER                  => $userName,
            GROUP                 => $groupName,
            HOME_DIR              => $homeDir,
            WEB_DIR               => $webDir,
            FORWARD               => $self->{'url_forward'} || 'no',
            FORWARD_TYPE          => $self->{'type_forward'} || '',
            WEB_FOLDER_PROTECTION => $self->{'web_folder_protection'}
        }
    } unless %{$self->{'_packages'}};

    $self->{'_packages'};
}

=item _sharedMountPoint()

 Does this domain alias share mount point with another domain?

 Return bool, die on failure

=cut

sub _sharedMountPoint
{
    my $self = shift;

    my $regexp = "^$self->{'alias_mount'}(/.*|\$)";
    my $db = iMSCP::Database->factory()->getRawDb();
    my ($nbSharedMountPoints) = $db->selectrow_array(
        "
            SELECT COUNT(mount_point) AS nb_mount_points FROM (
                SELECT alias_mount AS mount_point FROM domain_aliasses
                WHERE alias_id <> ? AND domain_id = ? AND alias_status NOT IN ('todelete', 'ordered') AND alias_mount RLIKE ?
                UNION
                SELECT subdomain_mount AS mount_point FROM subdomain
                WHERE domain_id = ? AND subdomain_status != 'todelete' AND subdomain_mount RLIKE ?
                UNION
                SELECT subdomain_alias_mount AS mount_point FROM subdomain_alias
                WHERE subdomain_alias_status != 'todelete' AND alias_id IN (SELECT alias_id FROM domain_aliasses WHERE domain_id = ?)
                AND subdomain_alias_mount RLIKE ?
            ) AS tmp
        ",
        undef, $self->{'alias_id'}, $self->{'domain_id'}, $regexp, $self->{'domain_id'}, $regexp, $self->{'domain_id'},
        $regexp
    );

    die( $db->errstr ) if $db->err;
    ($nbSharedMountPoints || $self->{'alias_mount'} eq '/');
}

=item isValidCertificate($domainAliasName)

 Does the SSL certificate which belongs to that the domain alias is valid?

 Param string $domainAliasName Domain alias name
 Return bool TRUE if the domain SSL certificate is valid, FALSE otherwise

=cut

sub isValidCertificate
{
    my ($self, $domainAliasName) = @_;

    my $certFile = "$main::imscpConfig{'GUI_ROOT_DIR'}/data/certs/$domainAliasName.pem";
    my $openSSL = iMSCP::OpenSSL->new(
        'private_key_container_path' => $certFile,
        'certificate_container_path' => $certFile,
        'ca_bundle_container_path'   => $certFile
    );
    !$openSSL->validateCertificateChain();
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
