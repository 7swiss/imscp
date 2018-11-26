# i-MSCP Listener::Apache2::Tools::Proxy listener file
# Copyright (C) 2017 Laurent Declercq <l.declercq@nuxwin.com>
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

# Provides transparent access to i-MSCP tools (pma, webmail...) through customer domains. For instance:
#
#  http://customer.tld/webmail/ will be redirected to https://customer.tld/webmail/ if ssl is enabled for customer domain
#  http://customer.tld/webmail/ will proxy to i-MSCP webmail transparently if ssl is not enabled for customer domain
#  https://customer.tld/webmail/ will proxy to i-MSCP webmail transparently
#

package Listener::Apache2::Tools::Proxy;

use strict;
use warnings;
use iMSCP::EventManager;
use iMSCP::TemplateParser qw/ getBlocByRef process replaceBlocByRef /;

iMSCP::EventManager->getInstance()->register( 'beforeHttpdBuildConf', sub
{
    my ( $cfgTpl, $tplName, $data ) = @_;

    return unless $tplName eq 'domain.tpl' && grep ( $_ eq $data->{'VHOST_TYPE'}, ( 'domain', 'domain_ssl' ) );

    if ( $data->{'VHOST_TYPE'} eq 'domain' && $data->{'SSL_SUPPORT'} ) {
        replaceBlocByRef(
            "# SECTION addons BEGIN.\n",
            "# SECTION addons END.\n",
            "    # SECTION addons BEGIN.\n"
                . getBlocByRef( "# SECTION addons BEGIN.\n", "# SECTION addons END.\n", $cfgTpl )
                . "    RedirectMatch 301 ^(/(?:ftp|pma|webmail)\/?)\$ https://$data->{'DOMAIN_NAME'}\$1\n"
                . "    # SECTION addons END.\n",
            $cfgTpl
        );
        return;
    }

    my $cfgProxy = ( $::imscpConfig{'PANEL_SSL_ENABLED'} eq 'yes' ) ? "    SSLProxyEngine On\n" : '';
    $cfgProxy .= <<'EOF';
    ProxyPass /ftp/ {HTTP_URI_SCHEME}{HTTP_HOST}:{HTTP_PORT}/ftp/ retry=1 acquire=3000 timeout=600 Keepalive=On
    ProxyPassReverse /ftp/ {HTTP_URI_SCHEME}{HTTP_HOST}:{HTTP_PORT}/ftp/
    ProxyPass /pma/ {HTTP_URI_SCHEME}{HTTP_HOST}:{HTTP_PORT}/pma/ retry=1 acquire=3000 timeout=600 Keepalive=On
    ProxyPassReverse /pma/ {HTTP_URI_SCHEME}{HTTP_HOST}:{HTTP_PORT}/pma/
    ProxyPass /webmail/ {HTTP_URI_SCHEME}{HTTP_HOST}:{HTTP_PORT}/webmail/ retry=1 acquire=3000 timeout=600 Keepalive=On
    ProxyPassReverse /webmail/ {HTTP_URI_SCHEME}{HTTP_HOST}:{HTTP_PORT}/webmail/
EOF
    replaceBlocByRef(
        "# SECTION addons BEGIN.\n",
        "# SECTION addons END.\n",
        "    # SECTION addons BEGIN.\n"
            . getBlocByRef( "# SECTION addons BEGIN.\n", "# SECTION addons END.\n", $cfgTpl )
            . process(
            {
                HTTP_URI_SCHEME => ( $::imscpConfig{'PANEL_SSL_ENABLED'} eq 'yes' ) ? 'https://' : 'http://',
                HTTP_HOST       => $::imscpConfig{'BASE_SERVER_VHOST'},
                HTTP_PORT       => $::imscpConfig{'PANEL_SSL_ENABLED'} eq 'yes'
                    ? $::imscpConfig{'BASE_SERVER_VHOST_HTTPS_PORT'} : $::imscpConfig{'BASE_SERVER_VHOST_HTTP_PORT'}
            },
            $cfgProxy
        )
            . "    # SECTION addons END.\n",
        $cfgTpl
    );
} );

1;
__END__
