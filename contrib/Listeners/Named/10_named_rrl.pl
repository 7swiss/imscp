# i-MSCP iMSCP::Listener::Named::Rrl listener file
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
## Implement RRL (Response Rate Limiting Feature for Bind9)
## See https://kb.isc.org/article/AA-00994/0/Using-the-Response-Rate-Limiting-Feature-in-BIND-9.10.html
## Note: Before use of this listener, you must ensure that your Bind9 version support RRL.
##
#

package iMSCP::Listener::Named::Rrl;

our $VERSION = '1.0.1';

use strict;
use warnings;
use File::Basename;
use iMSCP::EventManager;
use iMSCP::TemplateParser qw/ replaceBlocByRef /;
use iMSCP::Servers::Named;
use version;

#
## Configuration variables
#

# Max responses per second
my $responsesPerSecond = 10;

#
## Please, don't edit anything below this line
#

version->parse( "$main::imscpConfig{'PluginApi'}" ) >= version->parse( '1.5.1' ) or die(
    sprintf( "The 10_named_rrl.pl listener file version %s requires i-MSCP >= 1.6.0", $VERSION )
);

iMSCP::EventManager->getInstance()->register(
    'afterBind9BuildConfFile',
    sub {
        my ($cfgTpl, $cfgTplName) = @_;

        return 0 unless $cfgTplName eq basename( iMSCP::Servers::Named->factory()->{'config'}->{'NAMED_OPTIONS_CONF_FILE'} );

        replaceBlocByRef( "// imscp [{ENTRY_ID}] entry BEGIN\n", "// imscp [{ENTRY_ID}] entry ENDING\n", <<"EOF", $cfgTpl, 'preserveTags' );
    rate-limit {
        responses-per-second $responsesPerSecond;
    };
EOF
        0;
    }
) if index( $imscp::Config{'iMSCP::Servers::Named'}, '::Bind9::' ) != -1;

1;
__END__
