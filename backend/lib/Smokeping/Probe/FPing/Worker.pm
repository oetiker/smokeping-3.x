package Smokeping::Probe::FPing::Worker;

use strict;
use IPC::Open3;
use Symbol 'gensym';

=head1 NAME

Smokeping::Probe::FPing::Worker - FPing Probe Worker

=head1 DESCRITPION

The worker module gets loaded into a separate perl process by the smokeping
server. It runs independently of the main process, it gets probing tasks
assigned and reports back when it is done.

The worker part of the probes are not object oriented!

=head2 init

The init function gets called right after loading the worker. No arguments
are passed, but you can use it it do some general initialization work.

=cut

sub init {
    return 0;   
}

=head2 run(cfg,targets)

The run function gets called with two arguments. The probe configuration and
an array of targets to probe.

The function is expected to hash of path names and rrdupdate update argument strings.

=cut

sub run {
    my $cfg = shift;
    my $targets = shift;
    my $pings = $cfg->{pings};

    if ($cfg->{blazemode} || '' eq 'true'){
        $pings++;
    }

    my @addresses = map { $_ => $_->{host} } @$targets;
    my @options = @{$cfg->{options}} if $cfg->{options};
    my @cmd = (
       $cfg->{binary},
       '-C', $pings,
       qw(-q -B1 -r1),
       @options,
       @addresses
    );

    AnyEvent::Fork::RPC::event('debug',"Executing ".join(' ',@cmd));
    my $errh = gensym;
    my $pid = open3(my $inh,my $outh,$errh, @cmd) or die "starting fping: $!\n" ;
    my $fh = ( $cfg->{usestdout} || '') eq 'true' ? $outh : $errh;
    while (<$fh>){
        chomp;
   	    AnyEvent::Fork::RPC::event('debug',"Got fping output: '$_'");
        next unless /^\S+\s+:\s+[-\d\.]/; #filter out error messages from fping
        my @times = split /\s+/;
        my $ip = shift @times;
        next unless ':' eq shift @times; #drop the colon
        if ($cfg->{blazemode} || '' eq 'true'){     
             shift @times;
        }
        @times = map {sprintf "%.10e", $_ / 1000 } sort {$a <=> $b} grep /^\d/, @times;
    warn @times;
    }
    waitpid $pid,0;
    close $inh;
    close $outh;
    close $errh;
    return {};
}

1;
