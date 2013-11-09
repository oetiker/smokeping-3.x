package Smokeping::Command::burn;

use Mojo::Base 'Mojolicious::Command';
use Time::HiRes qw(gettimeofday);
use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);
use POSIX qw(strftime);
use Pod::Usage;
use Smokeping::Config;
use POSIX qw(strftime);
use AnyEvent::Loop;
use AnyEvent::Fork;
use AnyEvent::Fork::RPC;

has description => "run probes according to configuration.\n";
has usage       => <<"EOF";
usage: $0 burn [options]

smokeping.pl burn [options]

     --help           Print the manual page.

     --verbose        Send all loging output to the terminal.

     --noaction       Do everything except actually log any data to rrdtool

EOF

has config => sub {
    return shift->app->config;
};

use vars qw(%opt);

sub run {
    my ($self, @args) = @_;

    GetOptionsFromArray \@args, \%opt,qw(pod verbose noaction) or exit 1;

    if ($opt{help})     { pod2usage(-exitstatus => 0, -verbose => 2) }
    if ($opt{noaction}) { print STDERR "*** Runnning in NO ACTION mode ***\n"; $opt{verbose}=1 }
    
    if ($opt{pod}) { print $self->config->pod; exit 0 };

    $self->burn;
}


sub burn {
    my $self = shift;
    my $pool = $self->createProbes;
    my $cfg = $self->config->cfgHash;
    my $targets = $cfg->{Targets};
    my %timer;
    my %running;
    my %skipped;
    my %queue;
    my %rrdqueue;
    # schedule the tasks for the probes
    # note that a task can only get scheduled once his old
    # iteration has completed.
    for my $task ( @$targets ){
        $timer{task}{$task} = AnyEvent->timer(
            interval => $task->{step} || $cfg->{Probes}{$task->{probe}}{step},
            cb => sub {
                if ($running{$task}){
                    $self->log->warn("delay $task->{target} ($task->{probe}): still running");
                    $skipped{$task} = 1;
                }
                else {
                    $running{$task} = 1;               
                    push @{$queue{$task->{probe}}},$task;
                }
           }
       )
    }
    # have the probe look in their task list for work
    for my $probe (keys %$pool){
        my $targetcount = $pool->{$probe}{config}->targetCount;
        $timer{probe}{$probe} = AnyEvent->timer(
            interval => 1,
            cb => sub {
                my $target = $queue{$probe};
                return unless @$target;
                my @work;
                while (@$target){
                    push @work, shift @$target;
                    while (scalar @work < $targetcount and @$target){
                        push @work, shift @$target;
                    }
                    $pool->{$probe}{worker}->(
                        $cfg->{Probes}{$probe}->cfg,
                        \@work,
                        sub {
                            my $result = shift;
                            for my $path (keys %$result){
                                push @{$rrdqueue{$path}}, $result->{$path};
                            }
                            for my $task (@work){
                                if ($skipped{$task}){
                                    $skipped{$task} = 0;    
                                    push @{$queue{$probe}},$task;
                                }
                                else {
                                    $running{$task} = 0;
                                }
                            }
                        }
                    );
                }
            }
        );
    }

    AnyEvent::Loop::run;

}

sub createProbes {
    my $self = shift;;
    my $cfg = $self->config->cfgHash;   
    my %Probe;
    for my $key ( keys %{$cfg->{Probes}} ){
        my $probeCfg = $cfg->{Probes}{$key};
        my $probeModule = $probeCfg->probeModule;
        my $rpc = AnyEvent::Fork
           ->new
           ->require ("Smokeping::Probe::${probeModule}::Worker")
           ->AnyEvent::Fork::RPC::run(
                "Smokeping::Probe::${probeModule}::Worker::run",
                on_error   => sub { $self->app->log->error($_[0]) },
                on_event   => sub { $self->app->log->log(@_) },  
                serialiser =>  $AnyEvent::Fork::RPC::JSON_SERIALISER,
                load => 1,
                init => "Smokeping::Probe::${probeModule}::Worker::init",
                max => $probeCfg->maxWorkers,
           );
        $Probe{$key} = {
            worker => $rpc,
            config => $probeCfg
        };
    }
    return \%Probe;
}




1;

__END__

=head1 NAME

smoke.pm - Smokeping probe runner

=head1 SYNOPSIS

smokeping.pl B<smoke> [I<options>...]

     --man            Print the manual page of osp.

     --verbose        Send all loging output to the terminal.

     --noaction       Do everything except actually perform any changes.
                      This includes adding entries to  the database
                      but without commit.   

=head1 DESCRIPTION

In smoke mode, smokeping runs the probes configured, gathers the data and
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
