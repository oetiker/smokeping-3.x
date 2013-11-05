package Smokeping::Probe::Config;

=head1 NAME

Smokeping::Probe::Config - base class for Probe config modules

=head1 DESCRIPTION

Smokeping probes are split into two packages. The Config package which gets
loaded by the smokeping application and the Worker package which gets loaded
into a separate perl process to do the actual probing.

See L<Smokeping::Probe::FPing::Config> and L<Smokeping::Probe::FPing::Worker>
for an example.

=head1 AUTHOR

Tobias Oetiker E<lt>tobi@oetiker.chE<gt>

=cut

use Mojo::Base -base;

use Carp qw(croak);

has cfg => sub {
    croak "probe cfg hash must be provided when instanciating";
};

has probeName => sub {
    croak "probe name must be provided when instanciating";
};

has probeModule => sub {
    return shift->cfg->{probeModule};
};

has maxWorkers => sub {
    return shift->cfg->{maxWorkers};
};

has sourceFile => sub {
    __FILE__ 
};

has probeUnit => sub {
    return "Seconds";
};

has targetCount => sub {
    return 1;
};

has pod => sub {
    my $self = shift;
    my $pod = "";
    my $parser = Pod::Simple::PullParser->new;
    $parser->set_source($self->sourceFile);
    my $podhash = {
        name => $parser->get_name,
        description => $parser->get_description,
        author => $parser->get_author,
        variables => $self->pod_variables,
        synopsis => $self->pod_synopsis
    };
    for my $what (qw(name overview synopsis description variables authors notes bugs see_also)) {
        my $contents = $podhash->{$what};
 	    next if not defined $contents or $contents eq "";
	    my $headline = uc $what;
  	    $headline =~ s/_/ /; # see_also => SEE ALSO
		$pod .= "=head1 $headline\n\n";
		$pod .= $contents;
		chomp $pod;
		$pod .= "\n\n";
	}
	$pod .= "=cut";
    return $pod;
};


has step => sub {
    my $self = shift;
    return $self->properties->{step} 
       // $self->cfgHash->{Database}{step};
};

has pings => sub {
    my $self = shift;
    return $self->properties->{pings}
       // $self->cfgHash->{Database}{pings};
};


has probeVars => sub {
    return {
        step => {
  	        _re => '\d+',
            _example => 300,
	        _doc => <<DOC,
Duration of the base interval that this probe should use, if different
from the one specified in the 'Database' section. Note that the step in
the RRD files is fixed when they are originally generated, and if you
change the step parameter afterwards, you'll have to delete the old RRD
files or somehow convert them.
DOC
        },
        workers => {
            _re => '\d+',
	        _default => 4,
            _doc => <<DOC,
To work as efficiently as possibel, smokeping will operate multiple
instances of this probe, and distribute the pending work among these
instances. If you want to probe a great many targets, and have an
appropriate amount of mamory, you could easily set the number of workers to
100 or more. Note that some of the Smokeping probes like the FPing probe for
example are working on multiple targets internally, so there it does not
make much sense having multiple workers unless you have multiple sub probes
define which configure fping differently, and you want to enable them to run
in parallel.
DOC
        },
        pings => {
	        _re => '\d+',
            _sub => sub {
                my $val = shift;
                return "ERROR: The pings value must be at least 3."
                if $val < 3;
                return undef;
            },
	        _example => 10,
            _default => 10,
            _doc => <<'DOC',
How many pings should be sent to each target, if different from the global
value specified in the Database section. Note that the number of pings in
the RRD files is fixed when they are originally generated, and if you
change this parameter afterwards, you'll have to delete the old RRD
files or somehow convert them.
DOC
        },
        _mandatory => [],
    };
};

has targetVars => sub {
    return {
        step => {
            _re => '\d+',
            _example => 300,
            _doc => <<'DOC',
Override the period the probe is running at with a different step size.
Duration of the base query interval the system should use for this target.
Note that the step in the RRD files is fixed when they are originally
generated, and if you change the step parameter afterwards, you'll have to
delete the old RRD files or somehow convert them.
DOC
        },
        _mandatory => []
    };
};

# a helper method that combines two var hash references
# and joins their '_mandatory' lists.

sub mergeVars {
    my $self = shift;
	my $from = shift;
    my $to = shift;
	for (keys %$from) {
		if ($_ eq '_mandatory') {
			push @{$to->{_mandatory}}, @{$from->{$_}};
			next;
		}
		$to->{$_} = $from->{$_};
	}
	return $to;
}

has podSynopsis => sub {
	my $self = shift;
    $self =~ m/^Smokeping::Probe::(.+?)::Config/;
    my $probeName = $1;

	my $probeVars = $self->probeVars;
	my $targetVars = $self->targetVars;
	my $pod = <<DOC;
 *** Probes ***

 +$probeName

DOC
	$pod .= $self->podSynopsisVars($probeVars);
	my $targetpod = $self->podSynopsis($targetVars);
    $pod .= "\n # The following variables can be overridden in each target section\n$targetpod"
         if defined $targetpod and $targetpod ne "";
    $pod .= <<DOC;

 # [...]

 *** Targets ***

 probe = $probeName # if this should be the default probe

 # [...]

 + mytarget
 # probe = $probeName # if the default probe is something else
 host = host.mydomain
DOC
    $pod .= $targetpod
 	    if defined $targetpod and $targetpod ne "";
	return $pod;
};

# synopsis for one hash ref
sub podSynopsisVars {
    my $self = shift;
    my $vars = shift;
	my %mandatory;
	$mandatory{$_} = 1 for (@{$vars->{_mandatory}});
	my $pod = "";
	for (sort keys %$vars) {
		next if /^_mandatory$/;
		my $val = $vars->{$_}{_example};
		$val = $vars->{$_}{_default}
			if exists $vars->{$_}{_default}
			and not defined $val;
		$pod .= " $_ = $val";
		$pod .= " # mandatory" if $mandatory{$_};
		$pod .= "\n";
	}
	return $pod;
}

has podVariables => sub {
	my $self = shift;
	my $probeVars = $self->probeVars;
	my $pod = "Supported probe-specific variables:\n\n";
	$pod .= $self->podVaribablesProbe($probeVars);
	return $pod;
};

sub podVariablesProbe {
	my $class = shift;
	my $vars = shift;
	my $pod = "=over\n\n";
	my %mandatory;
	$mandatory{$_} = 1 for (@{$vars->{_mandatory}});
	for (sort keys %$vars) {
		next if /^_mandatory$/;
		$pod .= "=item $_\n\n";
		$pod .= $vars->{$_}{_doc};
		chomp $pod;
		$pod .= "\n\n";
		$pod .= "Example value: " . $vars->{$_}{_example} . "\n\n"
			if exists $vars->{$_}{_example};
		$pod .= "Default value: " . $vars->{$_}{_default} . "\n\n"
			if exists $vars->{$_}{_default};
		$pod .= "This setting is mandatory.\n\n"
			if $mandatory{$_};
	}
	$pod .= "=back\n\n";
	return $pod;
}

1;
