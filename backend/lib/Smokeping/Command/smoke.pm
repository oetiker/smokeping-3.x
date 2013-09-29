package SmokePing::Command::daemon;

use Mojo::Base 'Mojolicious::Command';
use Time::HiRes qw(gettimeofday);
use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);
use POSIX qw(strftime);
use Pod::Usage;
use IpLog::Config;
use IpLog::Util qw(ip2db);
use POSIX qw(strftime);

has description => "gather data according to probe configuration.\n";
has usage       => <<"EOF";
usage: $0 daemon [options]

iplog.pl daemon [options]

     --help           Print the manual page.

     --verbose        Send all loging output to the terminal.

     --noaction       Do everything except actually perform any changes.
                      This includes adding entries to  the database
                      but without commit.   

EOF

has 'config' => sub {
    my $self = shift;
    my $conf = IpLog::Config->new(
        app => $self->app,
        file => $ENV{SMOKEPING_CONF} || $self->app->home->rel_file('etc/smokeping.cfg' )
    );
    return $conf;
};

use vars qw(%opt);

sub run {
    my ($self, @args) = @_;

    GetOptionsFromArray \@args, \%opt,qw(pod verbose noaction) or exit 1;

    if ($opt{help})     { pod2usage(-exitstatus => 0, -verbose => 2) }
    if ($opt{noaction}) { print STDERR "*** Runnning in NO ACTION mode ***\n"; $opt{verbose}=1 }
    
    if ($opt{pod}) { print $self->config->pod; exit 0 };
}



1;

__END__

=head1 NAME

daemon.pm - SmokePing probe runner

=head1 SYNOPSIS

smokeping.pl B<daemon> [I<options>...]

     --man            Print the manual page of osp.

     --verbose        Send all loging output to the terminal.

     --noaction       Do everything except actually perform any changes.
                      This includes adding entries to  the database
                      but without commit.   

=head1 DESCRIPTION

In daemon mode, smokeping runs the probes configured, gathers the data and
updates the appropriate rrd files.

=head1 USAGE

...

=head1 COPYRIGHT

Copyright (c) 2013 by OETIKER+PARTNER AG. All rights reserved.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY 

 2013-09-27 to Initial

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
