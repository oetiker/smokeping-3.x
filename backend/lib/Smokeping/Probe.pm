package Smokeping::Probe;

=head1 NAME

Smokeping::Probe - Base Class for Smokeping Probes

=head1 SYNOPSIS

 my $pod = Smokeping::Probe->pod;
 my $targeCount = Smokeping::Probe->targetCount;
 my $style = Smokeping::Probe->rrdStyle;

 my $probe = AnyEvent::Fork
   ->new
   ->require ("Smokeping::Probe",Smokeping::Probe->requires)    
   ->AnyEvent::Fork::RPC::run ("Smokeping::Probe::run",
       on_error   => sub { warn "ERROR: $_[0]"; exit 1 },
   );

 my $probeRunner = AnyEvent->condvar;

 $probeRunner->cb(sub {
     my $targets = getTargets;
     $probe->($cfg,$targets, sub {
         my $rrdUpdates = shift;
         $rrdStack->push($rrdUpdates);
         $probeRunner->send;
     });
 });

 $probeRunner->send;
 $probeRunner->recv;

=head1 DESCRIPTION

Smokeping 3 Probes perform the task of measuring and probing data. Since
such activity is often rather tedious and involves lots of waiting for
measurement tasks to complete, the probes do not run in the main smokeping
process. They run in their own process thanks to the good services of
L<AnyEvent::Fork::Rpc>. The main smokeping process then hands out
measurement tasks to the probes and attaches a callback to feed the findings
on the rrdtool for storage.




use vars qw($VERSION);
use Mojo::base;
use Smokeping::style::Smokeping;

=head2 rrdStyle

has rrdStyle => sub {
    Smokeping::style::Smokeping->new;
};

=head2 taskCount

how many tasks can this probe run in parallel

=cut

has taskCount => sub {
    croak "override with the number of probing tasks this probe can perform in parallel";
}

=head2 probevars

what variables can the user configure as he creates an instance of this probe
in the config file

=cut

has probevars => sub {
    return {
	step => {
  	    _re => '\d+',
	    _example => 300,
	    _doc => <<DOC,
Interval for running this probe. By default it will run as often as
defined in the Database section. Note that the step in
the RRD files is fixed when they are originally generated, and if you
change the step parameter afterwards, you'll have to delete the old RRD
files or somehow convert them.                
DOC
        },
        instances => {
            _re => '\d+'
            _example => 1,
            _doc => <<DOC,
How many tasks should be running in paralle for this probe instance. Running
more tasks in parallel will generally make things faster, but if your probe
generates substantial load on the system or the network
DOC
            _default => 1
        },
	_mandatory => [],
    };
}

=head2 targetvars

what variables can be configured when using this probe in a target

=cut

has targetvars {
    return {_mandatory => []};
}

=head2 pod

the pod documentation for this probe

=cut

has pod => sub {
    my $self = shift;
    my %podhash;
    # magically read myself adding generated
    # synopsis and variables sections    
    $podhash->{synopsis} = $class->pod_synopsis;
    $podhash->{variables} = $class->pod_variables;
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
}

sub run {
    croak "this must be overridden by the subclass";
    my $tasks = shift;
    return __PACKAGE__->rrdStyle->updates($
}

sub round ($) {
    return sprintf "%.0f", $_[0];
}

sub ProbeDesc ($) {
    return "Probe which does not override the ProbeDesc method";
}    

sub ProbeUnit ($) {
    return "Seconds";
}    

# this is a read-only variable that should get incremented by
# the ping() method
sub rounds_count ($) {
    my $self = shift;
    return $self->{rounds_count};
}

sub increment_rounds_count ($) {
    my $self = shift;
    $self->{rounds_count}++;
}

sub target2dynfile ($$) {
    # the targets are stored in the $self->{targets}
    # hash as filenames pointing to the RRD files
    #
    # now that we use a (optionally) different dir for the
    # . adr files, we need to derive the .adr filename
    # from the RRD filename with a simple substitution

    my $self = shift;
    my $target = shift; # filename with <datadir> embedded
    my $dyndir =  $self->{cfg}{General}{dyndir};
    return $target unless defined $dyndir; # nothing to do
    my $datadir = $self->{cfg}{General}{datadir};
    $target =~ s/^\Q$datadir\E/$dyndir/;
    return $target;
}

sub rrdupdate_string($$)
{   my $self = shift;
    my $tree = shift;
#    print "$tree -> ", join ",", @{$self->{rtts}{$tree}};print "\n";    
    # skip invalid addresses
    my $pings = $self->_pings($tree);
    return "U:${pings}:".(join ":", map {"U"} 1..($pings+1)) 
        unless defined $self->{rtts}{$tree} and @{$self->{rtts}{$tree}} > 0;
    my $entries = scalar @{$self->{rtts}{$tree}};
    my @times = @{$self->{rtts}{$tree}};
    my $loss = $pings - $entries;
    my $median = $times[int($entries/2)] || 'U';
    # shift the data into the middle of the times array
    my $lowerloss = int($loss/2);
    my $upperloss = $loss - $lowerloss;
    @times = ((map {'U'} 1..$lowerloss),@times, (map {'U'} 1..$upperloss));
    my $age;
    my $dynbase = $self->target2dynfile($self->{targets}{$tree});
    if ( -f $dynbase.".adr" ) {
      $age =  time - (stat($dynbase.".adr"))[9];
    } else {
      $age = 'U';
    }
    if ( $entries == 0 ){
      $self->do_log("Warning: got zero answers from $tree->{addr}($tree->{probe}) $self->{targets}{$tree}");
      $age = 'U';
      $loss = 'U';
      if ( -f $dynbase.".adr"
	   and not -f $dynbase.".snmp" ){
	unlink $dynbase.".adr";
      }
    } ;
    return "${age}:${loss}:${median}:".(join ":", @times);
}

sub addresses($)
{
    my $self = shift;
    my $addresses = [];
    $self->{addrlookup} = {};
    foreach my $tree (keys %{$self->{targets}}){
        my $target = $self->{targets}{$tree};
        if ($target =~ m|/|) {
	   my $dynbase = $self->target2dynfile($target);
	   if ( open D, "<$dynbase.adr" ) {
	       my $ip;
	       chomp($ip = <D>);
	       close D;
	       
	       if ( open D, "<$dynbase.snmp" ) {
		   my $snmp = <D>;
		   chomp($snmp);
		   if ($snmp ne Smokeping::snmpget_ident $ip) {
		       # something fishy snmp properties do not match, skip this address
		       next;
		   }
                   close D;
	       }
	       $target = $ip;
	   } else {
	       # can't read address file skip
	       next;
	   }
	}
        $self->{addrlookup}{$target} = () 
                unless defined $self->{addrlookup}{$target};
        push @{$self->{addrlookup}{$target}}, $tree;
	push @{$addresses}, $target;
    };    
    return $addresses;
}

sub debug {
        my $self = shift;
        my $newval = shift;
        $self->{debug} = $newval if defined $newval;
        return $self->{debug};
}

sub do_debug {
        my $self = shift;
        return unless $self->debug;
        $self->do_log(@_);
}

sub do_fatal {
        my $self = shift;
        $self->do_log("Fatal:", @_);
        croak(@_);
}

sub do_log {
        my $self = shift;
        Smokeping::do_log("$self->{name}:", @_);
}

sub report {
	my $self = shift;
	my $count = $self->target_count;
	my $offset = $self->offset_in_seconds;
	my $step = $self->step;
	$self->do_log("probing $count targets with step $step s and offset $offset s.");
}

sub step {
	my $self = shift;
	my $rv = $self->{cfg}{Database}{step};
	unless (defined $self->{cfg}{General}{concurrentprobes}
	    and $self->{cfg}{General}{concurrentprobes} eq 'no') {
		$rv = $self->{properties}{step} if defined $self->{properties}{step};
	}
	return $rv;
}

sub offset {
	my $self = shift;
	my $rv = $self->{cfg}{General}{offset};
	unless (defined $self->{cfg}{General}{concurrentprobes}
	    and $self->{cfg}{General}{concurrentprobes} eq 'no') {
		$rv = $self->{properties}{offset} if defined $self->{properties}{offset};
	}
	return $rv;
}

sub offset_in_seconds {
	# returns the offset in seconds rather than as a percentage
	# this is filled in from the initialization in Smokeping::main
	my $self = shift;
	my $newval = shift;
	$self->{offset_in_seconds} = $newval if defined $newval;
	return $self->{offset_in_seconds};
}

# the "public" method that takes a "target" argument is used by the probes
# the "private" method that takes a "tree" argument is used by Smokeping.pm
# there's no difference between them here, but we have to provide both

sub pings {
	my $self = shift;
	my $target = shift;
	# $target is not used; basefork.pm overrides this method to provide a target-specific parameter
	my $rv = $self->{cfg}{Database}{pings};
	$rv = $self->{properties}{pings} if defined $self->{properties}{pings};
	return $rv;
}


sub _pings {
	my $self = shift;
	my $tree = shift;
	# $tree is not used; basefork.pm overrides this method to provide a target-specific parameter
	my $rv = $self->{cfg}{Database}{pings};
	$rv = $self->{properties}{pings} if defined $self->{properties}{pings};
	return $rv;
}

sub target_count {
	my $self = shift;
	$self->{target_count} = 0 if !defined $self->{target_count};
	return $self->{target_count};
}


# a helper method that combines two var hash references
# and joins their '_mandatory' lists.
sub _makevars {
	my ($class, $from, $to) = @_;
	for (keys %$from) {
		if ($_ eq '_mandatory') {
			push @{$to->{_mandatory}}, @{$from->{$_}};
			next;
		}
		$to->{$_} = $from->{$_};
	}
	return $to;
}

sub pod_synopsis {
	my $class = shift;
	my $classname = ref $class||$class;
	$classname =~ s/^Smokeping::probes:://;

	my $probevars = $class->probevars;
	my $targetvars = $class->targetvars;
	my $pod = <<DOC;
 *** Probes ***

 +$classname

DOC
	$pod .= $class->_pod_synopsis($probevars);
	my $targetpod = $class->_pod_synopsis($targetvars);
        $pod .= "\n # The following variables can be overridden in each target section\n$targetpod"
		if defined $targetpod and $targetpod ne "";
        $pod .= <<DOC;

 # [...]

 *** Targets ***

 probe = $classname # if this should be the default probe

 # [...]

 + mytarget
 # probe = $classname # if the default probe is something else
 host = my.host
DOC
        $pod .= $targetpod
		if defined $targetpod and $targetpod ne "";

	return $pod;
}

# synopsis for one hash ref
sub _pod_synopsis {
	my $class = shift;
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

sub pod_variables {
	my $class = shift;
	my $probevars = $class->probevars;
	my $pod = "Supported probe-specific variables:\n\n";
	$pod .= $class->_pod_variables($probevars);
	return $pod;
}

sub _pod_variables {
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
