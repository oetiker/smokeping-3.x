package SmokePing::Exception;

=head1 NAME

EP::Exception - a simple exception class

=head1 SYNOPSIS

 use EP::Exception qw(mkerror);

 eval { die error(22,'Bad Error'); }
 if ($@){
     print "Code: '.$@->code()." Message: ".$@->message()."\n"
     print "$@\n"; #stringified error
 }
 
=head1 DESCRIPTION

An error object to be used in remOcular code.

=over

=cut

use strict;
use warnings;

use Exporter 'import';
use vars qw(@EXPORT_OK);
@EXPORT_OK = qw(mkerror);

use overload ('""' => 'stringify');


use Mojo::Base -base;
has 'code';
has 'message';



=item B<mkerror>(I<code>,I<message>)

Create an nq::Exception object, setting code and message properties in the process.

=cut

sub mkerror {
    my $code = shift;
    my $message = shift;
    return (__PACKAGE__->new(code=>$code,message=>$message));
}

=item B<stringify>

error stringification handler

=cut

sub stringify {
    my $self = shift;
    return "ERROR ".$self->code().": ".$self->message();
}

1;
__END__

=back

=head1 LICENSE

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of   
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
 
You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 
=head1 COPYRIGHT

Copyright (c) 2010 by OETIKER+PARTNER AG. All rights reserved.

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2010-11-04 to 1.0 first version

=cut

# Emacs Configuration
#
# Local Variables:
# mode: cperl
# eval: (cperl-set-style "PerlStyle")
# mode: flyspell
# mode: flyspell-prog
# End:
#
# vi: sw=4 et

