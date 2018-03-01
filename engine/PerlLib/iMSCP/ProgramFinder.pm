=head1 NAME

iMSCP::ProgramFinder - Program finder

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2018 Laurent Declercq <l.declercq@nuxwin.com>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA

package iMSCP::ProgramFinder;

use strict;
use warnings;
use File::Spec;

=head1 DESCRIPTION

 This library helps to test whether programs are available on the executable search path.

=head1 FUNCTIONS

=over 4

=item find( $program )

 Find full program path in $PATH

 Param string $program Progran to find
 Return string program path if the given program is found in $PATH and is executable, undef otherwise

=cut

sub find
{
    my $program = $_[0];

    for my $path ( File::Spec->path() ) {
        my $file = File::Spec->catfile( $path, $program );
        return $file if -x $file;
    }

    undef;
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
