=head1 NAME

 iMSCP::Packages - Package that allows to load and get list of available i-MSCP packages

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

package iMSCP::Packages;

use strict;
use warnings;
use File::Basename;
use parent 'iMSCP::Common::Singleton';

=head1 DESCRIPTION

 Package that allows to load and get list of available i-MSCP packages

=head1 PUBLIC METHODS

=over 4

=item getList( )

 Get package list

 Return package list, sorted in descending order of priority

=cut

sub getList
{
    @{$_[0]->{'packages'}};
}

=item getListWithFullNames( )

 Get package list with full names, sorted in descending order of priority

 Return package list

=cut

sub getListWithFullNames
{
    @{$_[0]->{'packages_full_names'}};
}

=back

=head1 PRIVATE METHODS

=over 4

=item _init( )

 Initialize instance
 
 Return iMSCP::Packages, die on failure

=cut

sub _init
{
    my ($self) = @_;
    
    my $packageRootDir = dirname( __FILE__ );
    
    $_ = basename( $_, '.pm' ) for @{$self->{'packages'}} = glob ( "$packageRootDir/Packages/*.pm" );

    # In installer/uninstaller contexts, we also load setup packages
    if( grep( iMSCP::Getopt->context() eq $_, 'installer', 'uninstaller' ) ) {
        $_ = 'Setup::' .basename( $_, '.pm' ) for my @setupPackages = glob ( "$packageRootDir/Packages/Setup/*.pm" );
        push @{$self->{'packages'}}, @setupPackages;
    }

    # Load all package classes
    for ( @{$self->{'packages'}} ) {
        my $package = "iMSCP::Packages::${_}";
        eval "require $package; 1" or die( sprintf( "Couldn't load %s package class: %s", $package, $@ ));
    }

    # Sort packages by priority (descending order)
    @{$self->{'packages'}} = sort { "iMSCP::Packages::${b}"->getPriority() <=> "iMSCP::Packages::${a}"->getPriority() } @{$self->{'packages'}};
    @{$self->{'packages_full_names'}} = map { "iMSCP::Packages::${_}" } @{$self->{'packages'}};
    $self;
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
