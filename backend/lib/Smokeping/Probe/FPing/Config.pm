package Smokeping::Probe::FPing::Config;

use Mojo::Base qw(Smokeping::Probe::Config);

=pod

=head1 NAME

Smokeping::probes::FPing - FPing Probe for Smokeping

=head1 DESCRIPTION

Integrates FPing as a probe into smokeping. The variable B<binary> must
point to your copy of the FPing program. If it is not installed on your
system yet, get your copy from L<http:/www.fping.org>. Note that fping must
be installed setuid root to work.
  
Since version 3.3 fping sends its statistics to stdout. Set B<usestdout> to 'true'
so make smokeping read stdout instead of stderr.

In B<blazemode>, FPing sends one more ping than requested, and discards
the first RTT value returned as it's likely to be an outlier.

The FPing manpage has the following to say on this topic:

Number of bytes of ping data to send.  The minimum size (normally 12) allows
room for the data that fping needs to do its work (sequence number,
timestamp).  The reported received data size includes the IP header
(normally 20 bytes) and ICMP header (8 bytes), so the minimum total size is
40 bytes.  Default is 56, as in ping. Maximum is the theoretical maximum IP
datagram size (64K), though most systems limit this to a smaller,
system-dependent number.

=head1 AUTHORS

Tobias Oetiker <tobi@oetiker.ch>

=cut

# this is needed to be able to extract the pod
# documentation
has sourceFile => sub { __FILE __ }; 

has probeDesc => sub {
    my $self = shift;
    return $self->properties->{desctiption}
};

has probeUnit => sub {
    return "Seconds";
};

has targetCount => sub {
    return 1_000;
};

has probeVars => sub {
    my $self = shift;
    return $self->mergeVars(
		$self->SUPER::probeVars, 
        {
			_mandatory => [ 'binary' ],
			binary => {
            	_sub => sub {
 				    my ($val) = @_;
        	        return "ERROR: FPing 'binary' does not point to an executable"
                    unless -f $val and -x _;
		            return undef;
	            },
	            _doc => "The location of your fping binary.",
                _example => '/usr/bin/fping',
            },
            description => {
                _doc => "Short text string of fpings behaviour",
                _default => "ICMP Pings",
            },
	        blazemode => {
		        _re => '(true|false)',
		        _example => 'true',
		        _doc => "Send an extra ping and then discarge the first answer since the first is bound to be an outliner.",
	        },
	        usestdout => {
		        _re => '(true|false)',
	    	    _example => 'true',
		        _doc => "Listen for FPing output on stdout instead of stderr ... (version 3.3 sends its statistics on stdout).",
	        },
	        options => {
		        _doc => <<DOC,
The fping command is highly configurable. You can set the packet size, the interval between pings, type
of service, source address, ... See the documentation in the fping manual page.
DOC
	        }
        }
    );
};

1;
