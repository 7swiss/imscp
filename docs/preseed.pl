# i-MSCP preseed.pl template file for installer preseeding feature
#
# See the documentation at http://wiki.i-mscp.net/doku.php?id=start:preseeding
#
# Author: Laurent Declercq <l.declercq@nuxwin.com>
# Last update: 2018.02.14

%::questions = (
    # Mandatory parameters
    #
    # Parameters below must be filled. There is no default value for them.

    # Panel administrator password
    #
    # Only ASCII alphabet characters and numbers are allowed in password.
    ADMIN_PASSWORD                      => '',

    # System administrator email address
    #
    # Possible value: A valid email address.
    #
    # Bear mind that mails sent to local root user will be forwarded to that
    # email.
    DEFAULT_ADMIN_ADDRESS               => '',

    # SQL root user (mandatory)
    #
    # This SQL user must have full privileges on the SQL server.
    # Note that this user used only while i-MSCP installation/reconfiguration.
    #
    # Leave empty for default: root
    SQL_ROOT_USER                       => '',
    # Ignored when the (system) root user can connect without password (like 
    # in recent Debian versions).
    #
    SQL_ROOT_PASSWORD                   => '',

    # Optional parameters
    #
    # Parameters below are optional. If they are not filled, default value
    # will be used.

    # IPv6 support
    #
    # Possible values: yes, no
    #
    # Bear in mind that if IPv6 support is disabled on your system, setting
    # this parameter to 'yes' will not change anything.
    #
    # Leave empty for autodetection
    IPV6_SUPPORT                        => '',

    # Server hostname
    #
    # Possible values: A fully qualified hostname name
    #
    # Leave empty for autodetection: $(hostname --fqdn)
    SERVER_HOSTNAME                     => '',

    # Server primary IP
    #
    # Possible values: An already configured IPv4, IPv6 or `None'
    #
    # The `None' option is more suitable for Cloud computing services such as
    # Scaleway and Amazon EC2, or when using a Vagrant box where the public IP
    # address that is assigned through DHCP can changes over the time.
    #
    # Selecting the `None' option means that i-MSCP will configure the
    # services to listen on all interfaces.
    #
    # Leave empty for default: None
    BASE_SERVER_IP                      => '',

    # WAN IP (only relevant if your primary IP is in private range)
    #
    # Possible values: Ipv4 or IPv4
    #
    # You can force the use of the private IP address by using the same value as
    # the BASE_SERVER_IP parameter.
    #
    # Leave empty for public IP address automatic detection.
    BASE_SERVER_PUBLIC_IP               => '',

    # Timezone
    #
    # Possible values: A valid timezone such as Europe/Paris
    # (see http://php.net/manual/en/timezones.php)
    #
    # Leave empty for autodetection.
    TIMEZONE                            => '',

    # i-MSCP backup feature (database and configuration files)
    #
    # Possible values: yes, no
    #
    # Leave empty for default: yes
    BACKUP_IMSCP                        => '',

    # Enable backup feature for customers
    #
    # Possible values: yes, no
    #
    # Leave empty for default: yes
    BACKUP_DOMAINS                      => '',

    # SQL server implementation
    #
    # Possible values, depending on your distributions:
    # - Debian-like distributions:
    #  - iMSCP::Servers:Sqld::Mariadb::Debian (Default for Debian Buster)
    #  - iMSCP::Servers:Sqld::Mysql::Debian   (default for Debian/Devuan Jessie, Ubuntu Trusty/Xenial, not available for Debian Buster)
    #  - iMSCP::Servers:Sqld::Percona::Debian (Not available for Debian Buster)
    #  - iMSCP::Servers:Sqld::Remote::Debian
    #
    # Note that it is not possible to choose SQL server version in preseed mode.
    # The installer will automatically choose the newest available version.
    #
    # Leave empty for default: Depend on distribution and codename.
    'iMSCP::Servers::Sqld'              => '',

    # Database name
    #
    # Leave empty for default: imscp
    DATABASE_NAME                       => '',

    # Databas hostname
    #
    # Possible values: A valid hostname or IP address
    #
    # Leave empty for default: localhost
    DATABASE_HOST                       => '',

    # Database port
    #
    # Note that this port is used only for connections through TCP.
    #
    # Possible values: A valid port
    #
    # Leave empty for default: 3306
    DATABASE_PORT                       => '',

    # i-MSCP Master SQL user
    #
    # That is the primary SQL user for i-MSCP. It is used to connect to database
    # and create/delete SQL users for your customers.
    #
    # Note that the debian-sys-maint, imscp_srv_user, mysql.user, root and
    # vlogger_user SQL users are not allowed.
    #
    # Leave empty for default: imscp_user
    DATABASE_USER                       => '',
    # Only ASCII alphabet characters and numbers are allowed in password.
    #
    # Leave empty for autogeneration.
    DATABASE_PASSWORD                   => '',

    # Database user host (only relevant for remote SQL server)
    #
    # Host from which SQL users created by i-MSCP are allowed to connect to the
    # SQL server.
    #
    # Possible values: A valid hostname or IP address
    #
    # Leave empty for default: BASE_SERVER_PUBLIC_IP
    DATABASE_USER_HOST                  => '',

    # Enable or disable prefix/suffix for customer SQL database names
    #
    # Possible values: behind, infront, none
    #
    # Leave empty for default: none.
    MYSQL_PREFIX                        => '',

    # Control panel hostname
    #
    # This is the hostname from which the control panel will be reachable
    #
    # Possible values: A fully qualified hostname name
    #
    # Leave empty for default: panel.SERVER_HOSTNAME[domain part]
    BASE_SERVER_VHOST                   => '',

    # Control panel http port
    #
    # Possible values: A port in the 1025-65535 range
    #
    # Leave empty for default: 8880
    BASE_SERVER_VHOST_HTTP_PORT         => '',

    # Control panel https port (only relevant if SSL is enabled for the control
    # panel (see below))
    #
    # Possible values: A port in the 1025-65535 range
    #
    # Leave empty for default: 8443
    BASE_SERVER_VHOST_HTTPS_PORT        => '',

    # Enable or disable SSL
    #
    # Possible values: yes, no
    #
    # Leave empty for default: yes
    PANEL_SSL_ENABLED                   => '',

    # Whether or not a self-signed SSL cettificate must be used
    #
    # Possible values: yes, no
    #
    # Leave empty for default: yes
    PANEL_SSL_SELFSIGNED_CERTIFICATE    => '',

    # Settings to use a certificate emitted by a Certificate Authority
    #
    # NOT relevant if you use a self-signed certificate.
    #
    # These files are only used during setup. If you want to change
    # those later (e.g.: when you renew the certificate) you must
    # either replace it through the panel or re-run the setup.
    #
    # SSL private key path
    PANEL_SSL_PRIVATE_KEY_PATH          => '',
    # SSL private key passphrase (only if the private key is encrypted)
    PANEL_SSL_PRIVATE_KEY_PASSPHRASE    => '',
    # SSL certificate path
    PANEL_SSL_CERTIFICATE_PATH          => '',
    # SSL CA Bundle path (or root certificate if your CA doesn't use
    # intermediates)
    PANEL_SSL_CA_BUNDLE_PATH            => '',

    # Alternative URLs feature for client domains
    #
    # Possible values: yes, no
    #
    # Leave empty for default: yes
    CLIENT_DOMAIN_ALT_URLS              => '',

    # Control panel default access mode (only relevant if SSL is enabled)
    #
    # Possible values: http://, https://
    #
    # Leave empty for default: http://
    BASE_SERVER_VHOST_PREFIX            => '',

    # Master administrator login
    #
    # Leave empty for default: admin
    ADMIN_LOGIN_NAME                    => '',

    # DNS server implementation
    #
    # Possible values:
    # - Debian-like distributions:
    #   - iMSCP::Servers::Named::Bind9::Debian
    #   - iMSCP::Servers::NoServer
    #
    # Leave empty for default: iMSCP::Servers::Named::Bind9::Debian
    'iMSCP::Servers::Named'             => '',

    # DNS server mode (Only relevant with 'bind')
    #
    # Possible values: master, slave
    #
    # Leave empty for default: master
    NAMED_MODE                          => '',

    # Primary DNS server IP addresses (only relevant in slave mode)
    #
    # Possible value: 'no' or a list of IPv4/IPv6 each separated by semicolon
    # or space
    #
    # Leave empty for default: no
    NAMED_PRIMARY_DNS                   => '',

    # Slave DNS server IP addresses (only relevant in master mode)
    #
    # Possible value: 'no' or a list of IPv4/IPv6 each separated by semicolon
    # or space
    #
    # Leave empty for default: no
    NAMED_SECONDARY_DNS                 => '',

    # DNS IPv6 support
    #
    # Possible values: yes, no
    #
    # Leave empty for default: no
    NAMED_IPV6_SUPPORT                  => '',

    # Local DNS resolver (only relevant with 'bind')
    #
    # Possible values: yes, no
    #
    # Leave empty for default: yes
    NAMED_LOCAL_DNS_RESOLVER            => '',

    # Cron server implementation
    #
    # Possible values, depending on your distribution:
    # - Debian-like distributions:
    #   - iMSCP::Servers::Cron::Vixie::Debian   (Historical CRON(8) daemon)
    #   - iMSCP::Servers::Cron::Systemd::Debian (cron daemon functionality as provided by SYSTEMD.CRON(7), not available for Ubuntu Trusty)
    #
    # Leave empty for default: iMSCP::Servers::Cron::Vixie::Debian
    'iMSCP::Servers::Cron'              => '',

    # HTTPd server implementation
    #
    # Possible values:
    # - Debian-like distributions:
    #   - iMSCP::Servers::Httpd::Apache2::Debian
    #
    # Leave empty for default: iMSCP::Servers::Httpd::Apache2
    'iMSCP::Servers::Httpd'             => '',

    # Apache2 MPM (only relevant for the Apache2 httpd server)
    #
    # Possibles values: event, itk, prefork, worker
    #
    # Leave empty for default: event
    HTTPD_MPM                           => '',

    # PHP version for customers
    #
    # Possible values:
    # - Debian-like distributions:
    #   - 5.6 (default)
    #   - 7.0 
    #   - 7.1
    #   - 7.2 
    #
    # Leave empty for default: 5.6
    PHP_VERSION                         => '',

    # PHP SAPI for customers
    #
    # Possible values: apache2handler, cgi, fpm
    #
    # Restrictions:
    # - The apache2handler PHP SAPI require the Apache2 server with the itk MPM
    # - The cgi (cgi/FastCGI) PHP sapi cannot be used with the Apache2 itk MPM
    #   as the Apache's Fcgid module doesn't work with that MPM.
    #
    # Leave empty for default: fpm
    PHP_SAPI                            => '',

    # PHP-FPM FastCGI connection type
    #
    # This parameter is only relevant with the fpm PHP SAPI.
    #
    # Possible values: uds, tcp
    #
    # Leave empty for default: uds
    PHP_FPM_LISTEN_MODE                 => '',

    # FTPd server implementation
    #
    # Possible values:
    # - Debian-like distributions:
    #   - iMSCP::Servers::Ftpd::Proftpd::Debian
    #   - iMSCP::Servers::Ftpd::Vsftpd::Debian
    #
    # Leave empty for default: iMSCP::Servers::Ftpd::Proftpd::Debian 
    'iMSCP::Servers::Ftpd'              => '',

    # FTPd maximum client
    #
    # Possible values: 'none' for no limit, a number in range 1..1000
    #
    # See http://www.proftpd.org/docs/directives/linked/config_ref_MaxInstances.html
    #
    # Leave empty for default: 100
    FTPD_MAX_CLIENTS                    => '',

    # FTPd maximum number of clients allowed to connect per IP
    #
    # Possible values: 'none' for no limit, a number in range 1..1000
    #
    # http://www.proftpd.org/docs/directives/linked/config_ref_MaxClientsPerHost.html
    #
    # Leave empty for default: 20
    FTPD_MAX_CLIENTS_PER_IP             => '',

    # FTP SQL user
    #
    # Only ASCII alphabet characters and numbers are allowed in password.
    #
    # Leave empty for default: imscp_srv_user
    FTPD_SQL_USER                       => '',
    # Only ASCII alphabet characters and numbers are allowed in password.
    #
    # Leave empty for autogeneration.
    FTPD_SQL_PASSWORD                   => '',

    # Passive port range
    #
    # Possible values: A valid port range in the 32768-60999 range.
    #
    # Don't forgot to forward TCP traffic on those ports on your server if
    # you're behind a firewall.
    #
    # Leave empty for default: 32800 33800
    FTPD_PASSIVE_PORT_RANGE             => '',

    # MTA server implementation
    #
    # Possible values: postfix
    #
    # Leave empty for default: postfix
    'iMSCP::Servers::Mta'               => '',

    # MTA database driver (only relevant for postfix)
    #
    # Possible values: BTree, CDB, Hash
    #
    # Leave empty for default: CDB
    MTA_DB_DRIVER                       => '',

    # POP/IMAP servers implementation
    #
    # Possible values:
    # - Debian-like distributions:
    #   - iMSCP::Servers::Po::Courier::Debian
    #   - iMSCP::Servers::Po::Dovecot::Debian
    #
    # Leave empty for default: iMSCP::Servers::Po::Dovecot::Debian
    'iMSCP::Servers::Po'                => '',

    # Authdaemon SQL user (only relevant with 'courier')
    #
    # Only ASCII alphabet characters and numbers are allowed in password.
    #
    # Leave empty for default: imscp_srv_user
    PO_AUTHDAEMON_SQL_USER              => '',
    # Only ASCII alphabet characters and numbers are allowed in password.
    #
    # Leave empty for autogeneration.
    PO_AUTHDAEMON_SQL_PASSWORD          => '',

    # Dovecot SQL user (only relevant with 'dovecot')
    #
    # Only ASCII alphabet characters and numbers are allowed in password.
    #
    # Leave empty for default: imscp_srv_user
    PO_SQL_USER                         => '',
    # Only ASCII alphabet characters and numbers are allowed in password.
    #
    # Leave empty for autogeneration.
    PO_SQL_PASSWORD                     => '',

    # Enable or disable SSL for FTP/Mail services
    #
    # Possible values: yes, no
    #
    # Leave empty for default: yes
    SERVICES_SSL_ENABLED                => '',

    # Whether or not a self-signed SSL certificate must be used
    # Only relevant if SSL is enabled for the FTP/Mail services
    #
    # Possible values: yes, no
    #
    # Leave empty for default: yes
    SERVICES_SSL_SELFSIGNED_CERTIFICATE => '',

    # Settings to use a certificate emitted by a Certificate Authority
    # for the services.
    #
    # NOT relevant if you use a self-signed certificate.
    #
    # These files are only used during setup. If you want to change
    # those later (e.g.: when you renew the certificate) you must
    # either replace it through the panel or re-run the setup.
    #
    # SSL private key path
    SERVICES_SSL_PRIVATE_KEY_PATH       => '',
    # SSL private key passphrase (only if the private key is encrypted)
    SERVICES_SSL_PRIVATE_KEY_PASSPHRASE => '',
    # SSL certificate path
    SERVICES_SSL_CERTIFICATE_PATH       => '',
    # SSL CA Bundle path (or root certificate if your CA doesn't use
    # intermediates)
    SERVICES_SSL_CA_BUNDLE_PATH         => '',

    # Webstats package
    #
    # Possible values: 'no' or a list of comma separated packages names.
    # Available packages:
    # - Awstats (default)
    #
    # Leave empty for default.
    WEBSTATS_PACKAGES                   => '',

    # FTP Web file manager packages
    #
    # Possible values: 'no' or a list of comma separated packages names.
    # Available packages:
    # - no
    # - Pydio (currently not available due to PHP version constraint that is not met)
    # - MonstaFTP (default)
    #
    # Leave empty for default.
    FILEMANAGER_PACKAGE                 => '',

    # SQL user for PhpMyAdmin
    #
    # Leave empty for default: imscp_srv_user
    PHPMYADMIN_SQL_USER                 => '',
    # Only ASCII alphabet characters and numbers are allowed in password.
    #
    # Leave empty for autogeneration.
    PHPMYADMIN_SQL_PASSWORD             => '',

    # Webmmail packages
    #
    # Possible values: 'no' or a list of comma separated packages names.
    # Available packages:
    # - no
    # - RainLoop (default)
    # - Roundcube (default)
    #
    # Leave empty for default.
    WEBMAIL_PACKAGES                    => '',

    # SQL user for Roundcube package (only if you use Roundcube)
    #
    # Leave empty for default: imscp_srv_user
    ROUNDCUBE_SQL_USER                  => '',
    # Only ASCII alphabet characters and numbers are allowed in password.
    #
    # Leave empty for autogeneration.
    ROUNDCUBE_SQL_PASSWORD              => '',

    # SQL user for Rainloop package (only relevant if you use Rainloop)
    #
    # Leave empty for default: imscp_srv_user
    RAINLOOP_SQL_USER                   => '',
    # Only ASCII alphabet characters and numbers are allowed in password.
    #
    # Leave empty for autogeneration.
    RAINLOOP_SQL_PASSWORD               => '',

    # Anti-rootkits packages
    #
    # Possible values:
    # - no
    # - Chkrootkit (default)
    # - Rkhunter (default)
    #
    # Leave empty for default. 
    ANTI_ROOTKITS_PACKAGES              => ''
);

1;
__END__
