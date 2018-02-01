=head1 NAME

 iMSCP::Modules::SubAlias - Module for processing of subdomain alias entities

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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

package iMSCP::Modules::SubAlias;

use strict;
use warnings;
use File::Spec;
use parent 'iMSCP::Modules::Abstract';

=head1 DESCRIPTION

 Module for processing of subdomain alias entities.

=head1 PUBLIC METHODS

=over 4

=item getEntityType( )

 Get entity type

 Return string entity type

=cut

sub getEntityType
{
    'Subdomain';
}

=item add()

 Add, change or enable the subdomain alias

 Return self, die on failure

=cut

sub add
{
    my ($self) = @_;

    eval { $self->SUPER::add(); };
    $self->{'_dbh'}->do(
        'UPDATE subdomain_alias SET subdomain_alias_status = ? WHERE subdomain_alias_id = ?', undef, $@ || 'ok', $self->{'subdomain_alias_id'}
    );
    $self;
}

=item delete()

 Delete the subdomain alias

 Return self, die on failure

=cut

sub delete
{
    my ($self) = @_;

    eval { $self->SUPER::delete(); };
    if ( $@ ) {
        $self->{'_dbh'}->do( 'UPDATE subdomain_alias SET subdomain_alias_status = ? WHERE domain_id = ?', undef, $@, $self->{'subdomain_alias_id'} );
        return $self;
    }

    $self->{'_dbh'}->do( 'DELETE FROM subdomain_alias WHERE subdomain_alias_id = ?', undef, $self->{'subdomain_alias_id'} );
    $self;
}

=item disable()

 Disable the subdomain alias

 Return self, die on failure

=cut

sub disable
{
    my ($self) = @_;

    eval { $self->SUPER::disable(); };
    $self->{'_dbh'}->do(
        'UPDATE subdomain_alias SET subdomain_alias_status = ? WHERE subdomain_alias_id = ?', undef, $@ || 'disabled', $self->{'subdomain_alias_id'}
    );
    $self;
}

=item restore()

 Restore the subdomain alias

 Return self, die on failure

=cut

sub restore
{
    my ($self) = @_;

    eval { $self->SUPER::restore(); };
    $self->{'_dbh'}->do( 'UPDATE subdomain_alias SET subdomain_alias_status = ? WHERE subdomain_alias_id = ?', undef, $@ || 'ok',
        $self->{'domain_id'} );
    $self;
}

=item handleEntity( $subAliasId )

 Handle the given subdomain alias entity

 Param int $subAliasId Subdomain alias unique identifier
 Return self, die on failure

=cut

sub handleEntity
{
    my ($self, $subAliasId) = @_;

    $self->_loadData( $subAliasId );

    if ( $self->{'subdomain_alias_status'} =~ /^to(?:add|change|enable)$/ ) {
        $self->add();
    } elsif ( $self->{'subdomain_alias_status'} eq 'todelete' ) {
        $self->delete();
    } elsif ( $self->{'subdomain_alias_status'} eq 'todisable' ) {
        $self->disable();
    } elsif ( $self->{'subdomain_alias_status'} eq 'torestore' ) {
        $self->restore();
    } else {
        die( sprintf( 'Unknown action (%s) for subdomain alias (ID %d)', $self->{'subdomain_alias_status'}, $subAliasId ));
    }

    $self;
}

=back

=head1 PRIVATE METHODS

=over 4

=item _loadData( $subAliasId )

 Load data

 Param int $subAliasId Subdomain alias unique identifier
 Return void, die on failure

=cut

sub _loadData
{
    my ($self, $subAliasId) = @_;

    my $row = $self->{'_dbh'}->selectrow_hashref(
        "
            SELECT t1.*,
                t2.alias_name, t2.external_mail, t3.domain_name AS user_home,
                t3.domain_id, t3.domain_admin_id, t3.domain_mailacc_limit, t3.domain_php, t3.domain_cgi,
                t3.web_folder_protection, t3.phpini_perm_config_level AS php_config_level,
                IFNULL(t4.ip_number, '0.0.0.0') AS ip_number,
                t5.private_key, t5.certificate, t5.ca_bundle, t5.allow_hsts, t5.hsts_max_age,
                t5.hsts_include_subdomains,
                t6.mail_on_domain
            FROM subdomain_alias AS t1
            JOIN domain_aliasses AS t2 USING(alias_id)
            JOIN domain AS t3 USING (domain_id)
            LEFT JOIN server_ips AS t4 ON (t4.ip_id = t2.alias_ip_id)
            LEFT JOIN ssl_certs AS t5 ON(
                t5.domain_id = t1.subdomain_alias_id AND t5.domain_type = 'alssub' AND t5.status = 'ok'
            )
            LEFT JOIN (
                SELECT sub_id, COUNT(sub_id) AS mail_on_domain
                FROM mail_users
                WHERE mail_type LIKE 'alssub\\_%'
                GROUP BY sub_id
            ) AS t6 ON (t6.sub_id = t1.subdomain_alias_id)
            WHERE t1.subdomain_alias_id = ?
        ",
        undef,
        $subAliasId
    );
    $row or die( sprintf( 'Data not found for subdomain alias (ID %d)', $subAliasId ));
    %{$self} = ( %{$self}, %{$row} );
}

=item _getData( $action )

 Data provider method for servers and packages

 Param string $action Action
 Return hashref Reference to a hash containing data, die on failure

=cut

sub _getData
{
    my ($self, $action) = @_;

    return $self->{'_data'} if %{$self->{'_data'}};

    my $usergroup = $main::imscpConfig{'SYSTEM_USER_PREFIX'} . ( $main::imscpConfig{'SYSTEM_USER_MIN_UID'}+$self->{'domain_admin_id'} );
    my $homeDir = File::Spec->canonpath( "$main::imscpConfig{'USER_WEB_DIR'}/$self->{'user_home'}" );
    my $webDir = File::Spec->canonpath( "$homeDir/$self->{'subdomain_alias_mount'}" );
    my $documentRoot = File::Spec->canonpath( "$webDir/$self->{'subdomain_alias_document_root'}" );
    my ($ssl, $hstsMaxAge, $hstsIncSub, $phpini) = ( 0, 0, 0, {} );

    if ( $self->{'certificate'}
        && -f "$main::imscpConfig{'GUI_ROOT_DIR'}/data/certs/$self->{'subdomain_alias_name'}.$self->{'alias_name'}.pem.pem" ) {
        $ssl = 1;
        if ( $self->{'allow_hsts'} eq 'on' ) {
            $hstsMaxAge = $self->{'hsts_max_age'} || 0;
            $hstsIncSub = $self->{'hsts_include_subdomains'} eq 'on' ? '; includeSubDomains' : '';
        }
    }

    if ( $self->{'domain_php'} eq 'yes' ) {
        $phpini = $self->{'_dbh'}->selectrow_hashref(
            'SELECT * FROM php_ini WHERE domain_id = ? AND domain_type = ?',
            undef,
            ( $self->{'php_config_level'} eq 'per_user'
                ? $self->{'domain_id'} : ( $self->{'php_config_level'} eq 'per_domain' ? $self->{'alias_id'} : $self->{'subdomain_alias_id'} )
            ),
            ( $self->{'php_config_level'} eq 'per_user' ? 'dmn' : ( $self->{'php_config_level'} eq 'per_domain' ? 'als' : 'subals' ) )
        ) || {};
    }

    $self->{'_data'} = {
        ACTION                  => $action,
        STATUS                  => $self->{'subdomain_alias_status'},
        BASE_SERVER_VHOST       => $main::imscpConfig{'BASE_SERVER_VHOST'},
        BASE_SERVER_IP          => $main::imscpConfig{'BASE_SERVER_IP'},
        BASE_SERVER_PUBLIC_IP   => $main::imscpConfig{'BASE_SERVER_PUBLIC_IP'},
        DOMAIN_ADMIN_ID         => $self->{'domain_admin_id'},
        DOMAIN_ID               => $self->{'subdomain_alias_id'},
        DOMAIN_NAME             => $self->{'subdomain_alias_name'} . '.' . $self->{'alias_name'},
        DOMAIN_IP               => $main::imscpConfig{'BASE_SERVER_IP'} eq '0.0.0.0' ? '0.0.0.0' : $self->{'ip_number'},
        DOMAIN_TYPE             => 'alssub',
        PARENT_DOMAIN_NAME      => $self->{'alias_name'},
        ROOT_DOMAIN_NAME        => $self->{'user_home'},
        HOME_DIR                => $homeDir,
        WEB_DIR                 => $webDir,
        MOUNT_POINT             => $self->{'subdomain_alias_mount'},
        DOCUMENT_ROOT           => $documentRoot,
        SHARED_MOUNT_POINT      => $self->_sharedMountPoint(),
        USER                    => $usergroup,
        GROUP                   => $usergroup,
        PHP_SUPPORT             => $self->{'domain_php'},
        PHP_CONFIG_LEVEL        => $self->{'php_config_level'},
        PHP_CONFIG_LEVEL_DOMAIN => $self->{'php_config_level'} eq 'per_user'
            ? $self->{'user_home'}
            : ( $self->{'php_config_level'} eq 'per_domain' ? $self->{'alias_name'} : $self->{'subdomain_alias_name'} . '.' . $self->{'alias_name'} ),
        CGI_SUPPORT             => $self->{'domain_cgi'},
        WEB_FOLDER_PROTECTION   => $self->{'web_folder_protection'},
        SSL_SUPPORT             => $ssl,
        HSTS_SUPPORT            => $ssl && $self->{'allow_hsts'} eq 'on',
        HSTS_MAX_AGE            => $hstsMaxAge,
        HSTS_INCLUDE_SUBDOMAINS => $hstsIncSub,
        ALIAS                   => 'alssub' . $self->{'subdomain_alias_id'},
        FORWARD                 => $self->{'subdomain_alias_url_forward'} || 'no',
        FORWARD_TYPE            => $self->{'subdomain_alias_type_forward'} || '',
        FORWARD_PRESERVE_HOST   => $self->{'subdomain_alias_host_forward'} || 'Off',
        DISABLE_FUNCTIONS       => $phpini->{'disable_functions'}
            || 'exec,passthru,phpinfo,popen,proc_open,show_source,shell,shell_exec,symlink,system',
        MAX_EXECUTION_TIME      => $phpini->{'max_execution_time'} || 30,
        MAX_INPUT_TIME          => $phpini->{'max_input_time'} || 60,
        MEMORY_LIMIT            => $phpini->{'memory_limit'} || 128,
        ERROR_REPORTING         => $phpini->{'error_reporting'} || 'E_ALL & ~E_DEPRECATED & ~E_STRICT',
        DISPLAY_ERRORS          => $phpini->{'display_errors'} || 'off',
        POST_MAX_SIZE           => $phpini->{'post_max_size'} || 8,
        UPLOAD_MAX_FILESIZE     => $phpini->{'upload_max_filesize'} || 2,
        ALLOW_URL_FOPEN         => $phpini->{'allow_url_fopen'} || 'off',
        PHP_FPM_LISTEN_PORT     => ( $phpini->{'id'} // 1 )-1,
        EXTERNAL_MAIL           => $self->{'external_mail'},
        MAIL_ENABLED            => $self->{'external_mail'} eq 'off' && ( $self->{'mail_on_domain'} || $self->{'domain_mailacc_limit'} >= 0 )
    };
}

=item _sharedMountPoint( )

 Is the subdomain alias sharing a mount point with another domain?

 Return bool TRUE if the subdomain alias share a mount point with another domain, FALSE otherwise, die on failure

=cut

sub _sharedMountPoint
{
    my ($self) = @_;

    my $regexp = "^$self->{'subdomain_alias_mount'}(/.*|\$)";
    my ($nbSharedMountPoints) = $self->{'_dbh'}->selectrow_array(
        "
            SELECT COUNT(mount_point) AS nb_mount_points FROM (
                SELECT alias_mount AS mount_point FROM domain_aliasses
                WHERE domain_id = ? AND alias_status NOT IN ('todelete', 'ordered') AND alias_mount RLIKE ?
                UNION ALL
                SELECT subdomain_mount AS mount_point FROM subdomain
                WHERE domain_id = ? AND subdomain_status != 'todelete' AND subdomain_mount RLIKE ?
                UNION ALL
                SELECT subdomain_alias_mount AS mount_point FROM subdomain_alias
                WHERE subdomain_alias_id <> ? AND subdomain_alias_status != 'todelete'
                AND alias_id IN (SELECT alias_id FROM domain_aliasses WHERE domain_id = ?)
                AND subdomain_alias_mount RLIKE ?
            ) AS tmp
        ",
        undef, $self->{'domain_id'}, $regexp, $self->{'domain_id'}, $regexp, $self->{'subdomain_alias_id'}, $self->{'domain_id'}, $regexp
    );
    $nbSharedMountPoints || $self->{'subdomain_alias_mount'} eq '/';
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
