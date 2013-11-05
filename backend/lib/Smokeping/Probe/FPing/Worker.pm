package Smokeping::Probes::FPing::Worker;

use strict;
use IPC::Open3;

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
   
}

=head2 run(cfg,targets)

The run function gets called with two arguments. The probe configuration and
an array of targets to probe.

The function is expected to hash of path names and rrdupdate update argument strings.

=cut

sub run {
    my $cfg = shift;
    my $targets = shift;

    if ($cfg->{blazemode} || '') eq 'true'){
        $pings++;
    }
    my @cmd = (
                    $self->binary,
                    '-C', $pings, '-q','-B1','-r1',
		    @params,
                    @{$self->addresses});
    $self->do_debug("Executing @cmd");
    my $pid = open3($inh,$outh,$errh, @cmd);
    $self->{rtts}={};
    my $fh = ( $self->{properties}{usestdout} || '') eq 'true' ? $outh : $errh;
    while (<$fh>){
        chomp;
	$self->do_debug("Got fping output: '$_'");
        next unless /^\S+\s+:\s+[-\d\.]/; #filter out error messages from fping
        my @times = split /\s+/;
        my $ip = shift @times;
        next unless ':' eq shift @times; #drop the colon
        if (($self->{properties}{blazemode} || '') eq 'true'){     
             shift @times;
        }
        @times = map {sprintf "%.10e", $_ / $self->{pingfactor}} sort {$a <=> $b} grep /^\d/, @times;
        map { $self->{rtts}{$_} = [@times] } @{$self->{addrlookup}{$ip}} ;
    }
    waitpid $pid,0;
    close $inh;
    close $outh;
    close $errh;
}

sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {
		_mandatory => [ 'binary' ],
		binary => {
			_sub => sub {
				my ($val) = @_;
        			return undef if $ENV{SERVER_SOFTWARE}; # don't check for fping presence in cgi mode
				return "ERROR: FPing 'binary' does not point to an executable"
            				unless -f $val and -x _;
				return undef;
			},
			_doc => "The location of your fping binary.",
			_example => '/usr/bin/fping',
		},
		packetsize => {
			_re => '\d+',
			_example => 5000,
			_sub => sub {
				my ($val) = @_;
        			return "ERROR: FPing packetsize must be between 12 and 64000"
              				if ( $val < 12 or $val > 64000 ); 
				return undef;
			},
			_doc => "The ping packet size (in the range of 12-64000 bytes).",

		},
		blazemode => {
			_re => '(true|false)',
			_example => 'true',
			_doc => "Send an extra ping and then discarge the first answer since the first is bound to be an outliner.",

		},
		usestdout => {
			_re => '(true|false)',
			_example => 'true',
			_doc => "Listen for FPing output on stdout instead of stderr ... (version 3.3+ sends its statistics on stdout).",

		},
		timeout => {
			_re => '(\d*\.)?\d+',
			_example => 1.5,
			_doc => <<DOC,
The fping "-t" parameter, but in (possibly fractional) seconds rather than
milliseconds, for consistency with other Smokeping probes. Note that as
Smokeping uses the fping 'counting' mode (-C), this apparently only affects
the last ping.
DOC
		},
		hostinterval => {
			_re => '(\d*\.)?\d+',
			_example => 1.5,
			_doc => <<DOC,
The fping "-p" parameter, but in (possibly fractional) seconds rather than
milliseconds, for consistency with other Smokeping probes. From fping(1):

This parameter sets the time that fping  waits between successive packets
to an individual target.
DOC
		},
		mininterval => {
			_re => '(\d*\.)?\d+',
			_example => .001,
			_default => .01,
			_doc => <<DOC,
The fping "-i" parameter, but in (probably fractional) seconds rather than
milliseconds, for consistency with other Smokeping probes. From fping(1):

The minimum amount of time between sending a ping packet to any target.
DOC
		},
		sourceaddress => {
			_re => '\d+(\.\d+){3}',
			_example => '192.168.0.1',
			_doc => <<DOC,
The fping "-S" parameter . From fping(1):

Set source address.
DOC
		},
		tos => {
			_re => '\d+|0x[0-9a-zA-Z]+',
			_example => '0x20',
			_doc => <<DOC,
Set the type of service (TOS) of outgoing ICMP packets.
You need at laeast fping-2.4b2_to3-ipv6 for this to work. Find
a copy on www.smokeping.org/pub.
DOC
		},
	});
}

1;
