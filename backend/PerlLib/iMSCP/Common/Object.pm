=head1 NAME

 iMSCP::Common::Object - Object base class

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

package iMSCP::Common::Object;

use strict;
use warnings;

=head1 DESCRIPTION

 Object base class.

=head1 PUBLIC METHODS

=over 4

=item new( [ %attrs ] )

 Constructor

 Param hash|hashref OPTIONAL hash representing class attributes
 Return iMSCP::Common::Object

=cut

sub new
{
    my ( $class, @attrs ) = @_;

    # Already got an object
    return $class if ref $class;

    ( bless { @attrs && ref $attrs[0] eq 'HASH' ? %{ $attrs[0] } : @attrs }, $class )->_init();
}

=back

=head1 PRIVATE METHODS

=over 4

=item _init( )

 Initialize instance

 Return iMSCP::Common::Object

=cut

sub _init
{
    my ( $self ) = @_;

    $self;
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
