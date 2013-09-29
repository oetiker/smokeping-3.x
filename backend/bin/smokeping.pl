#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../thirdparty/lib/perl5";
use lib "$FindBin::Bin/../lib";
# use lib qw() # PERL5LIB
use Mojolicious::Commands;

# loading some modules just to be sure they are 
# present and can load
use Smokeping::Command::smoke;

our $VERSION = "0";

# Start commands
Mojolicious::Commands->start_app('Smokeping');

__END__

=head1 NAME

smokeping.pl - End to End Monitoring

=head1 SYNOPSIS

 smokeping.pl daemon
 smokeping.pl fcgi

=head1 DESCRIPTION

Smokeping runs in two modes. In deamon mode it runs the actual monitoring
tasks, gathering data by running probe modules. In server/fcgi mode it
provides a REST API for remote access.

Smokeping itself has no web fontend as such, but it integrates tightly with
L<Extopus|http://www.extopus.org> to provide a user friendly interface.
Extopus uses the REST API to communicate with the Smokeping instance.

Smokeping can run in slave mode, where it gets its configuration from a
Smokeping Master Server and also returns its findings to the master.

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

Copyright (c) 2013 by OETIKER+PARTNER AG. All rights reserved.

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2013-03-06 to 1.0 first version

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
