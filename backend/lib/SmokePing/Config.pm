package SmokePing::Config;

=head1 NAME

SmokePing::Config - The SmnokePing Config Reader Class

=head1 SYNOPSIS

 use SmokePing::Config;

 my $config = SmokePing::Config->new(file=>'/etc/smokeping.conf);

 my $cfg = $config->cfgHash();
 my $pod = $config->pod();

=head1 DESCRIPTION

Configuration reader Class for SmokePing

=head1 PROPERTIES

=cut

use Mojo::Base -base;
use Mojo::Util qw(hmac_sha1_sum);
use Storable qw(dclone);
use Carp;
use Config::Grammar::Dynamic;

use POSIX qw(strftime);

=head2 file

the name of the config file

=cut

has file => sub { croak "the file parameter is mandatory" };

=head2 app

the app object

=cut

has app => sub { croak "provide an app object" };

=head2 cfgHash

a hash containing the data from the config file

=cut

has cfgHash => sub {
    my $self = shift;
    my $cfg_file = shift;
    my $parser = $self->_make_parser();
    my $cfg = $parser->parse($self->file) or croak($parser->{err});
    $self->_postProcess($cfg);
    return $cfg;
};

=head2 pod

returns a pod documenting the config file

=cut

has pod => sub {
    my $self = shift;
    my $parser = $self->_make_parser();
    my $E = '=';
    my $header = <<"HEADER_END";
${E}head1 NAME

smokeping.cfg - The SmokePing configuration file

${E}head1 SYNOPSIS

 [...]

${E}head1 DESCRIPTION

The bwtr configuration is based on L<Config::Grammar>. The following options are available.

HEADER_END

    my $footer = <<"FOOTER_END";

${E}head1 COPYRIGHT

Copyright (c) 2013 by OETIKER+PARTNER AG. All rights reserved.

${E}head1 LICENSE

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

${E}head1 AUTHOR

S<Tobias Oetiker E<lt>tobi\@oetiker.chE<gt>>

${E}head1 HISTORY

 2013-03-06 to 1.0 first version

FOOTER_END

    return $header.$parser->makepod().$footer;
};


=head1 METHODS

All methods inherited from L<Mojo::Base>. As well as the following:

=head2 $x->B<_make_parser>()

Create a smokeping config parser.

=cut

sub _make_parser {
    my $self = shift;
    my $E = '=';

    my $KEYD_RE = '[-_0-9a-zA-Z]+';
    my $KEYDD_RE = '[-_0-9a-zA-Z.]+';

    my $pluginMap = {};

    for my $type (qw(probes matchers sorters)){
        for my $path (@INC){
            for my $file (glob($path.'/SmokePing/'.$type.'/[A-Z]*.pm')){
                my $plugin = $file;
                $plugin =~ s{.*/SmokePing/$type/(.*)\.pm}{$1};
                $probeList->{$type}{$plugin} =  "(See the L<separate module documentation|Smokeping::$type::$plugin> for detailed Information about each variable.)";
            }
        }
    }

    # The _dyn() stuff here is quite confusing, so here's a walkthrough:
    # 1   Probe is defined in the Probes section
    # 1.1 _dyn is called for the section to add the probe- and target-specific
    #     vars into the grammar for this section and its subsections (subprobes)
    # 1.2 A _dyn sub is installed for all mandatory target-specific variables so 
    #     that they are made non-mandatory in the Targets section if they are
    #     specified here. The %storedtargetvars hash holds this information.
    # 1.3 If a probe section has any subsections (subprobes) defined, the main
    #     section turns into a template that just offers default values for
    #     the subprobes. Because of this a _dyn sub is installed for subprobe
    #     sections that makes any mandatory variables in the main section non-mandatory.
    # 1.4 A similar _dyn sub as in 1.2 is installed for the subprobe target-specific
    #     variables as well.
    # 2   Probe is selected in the Targets section top
    # 2.1 _dyn is called for the section to add the probe- and target-specific
    #     vars into the grammar for this section and its subsections. Any _default
    #     values for the vars are removed, as they will be propagated from the Probes
    #     section.
    # 2.2 Another _dyn sub is installed for the 'probe' variable in target subsections
    #     that behaves as 2.1
    # 2.3 A _dyn sub is installed for the 'host' variable that makes the mandatory
    #     variables mandatory only in those sections that have a 'host' setting.
    # 2.4 A _sub sub is installed for the 'probe' variable in target subsections that
    #     bombs out if 'probe' is defined after any variables that depend on the
    #     current 'probe' setting.


    # The target-specific vars of each probe
    # We need to store them to relay information from Probes section to Target section
    # see 1.2 above
    my %storedtargetvars; 

    # the part of target section syntax that doesn't depend on the selected probe
    my $TARGETCOMMON; # predeclare self-referencing structures
    # the common variables
    my $TARGETCOMMONVARS = [ qw (probe menu title alerts note email host remark rawlog alertee slaves hide nomasterpoll /m-\S+/) ];

    $TARGETCOMMON =  {
        _vars     => $TARGETCOMMONVARS,
        _inherited=> [ qw (probe alerts alertee slaves nomasterpoll /m-\S+/) ],
        _sections => [ "/$KEYD_RE/" ],
        _recursive=> [ "/$KEYD_RE/" ],
        _sub => sub {
            my $val = shift;
            return "PROBE_CONF sections are neither needed nor supported any longer. Please see the smokeping_upgrade document."
                if $val eq 'PROBE_CONF';
            return undef;
        },
        "/$KEYD_RE/" => {},
        _order    => 1,
        _varlist  => 1,
        _doc => <<DOC,
Each target section can contain information about a host to monitor as
well as further target sections. Most variables have already been
described above. The expression above defines legal names for target
sections.
DOC
        '/m-\S+' => {
            _doc => <<DOC,
Extopus uses object properties to construct trees of all objects it can visualize
With the 'm-*' properties, you can define additional properties which can be used in extopus
to define the presentation tree.
DOC
        },
        alerts    => {
            _doc => 'Comma separated list of alert names',
            _re => '([^\s,]+(,[^\s,]+)*)?',
            _re_error => 'Comma separated list of alert names',
        },
        '/
        hide      => {
            _doc => <<DOC,
Set the hide property to 'yes' to hide this host from the navigation menu
and from search results. Note that if you set the hide property on a non
leaf entry all subordinate entries will also disapear in the menu structure.
If you know a direct link to a page it is still accessible. Pages which are
hidden from the menu due to a parent being hidden will still show up in
search results and in alternate hierarchies where they are below a non
hidden parent.
DOC
            _re => '(yes|no)',
            _default => 'no',
        },

        nomasterpoll=> {
            _doc => <<DOC,
Use this in a master/slave setup where the master must not poll a particular
target. The master will now skip this entry in its polling cycle.
Note that if you set the hide property on a non leaf entry
all subordinate entries will also disapear in the menu structure. You can
still access them via direct link or via an alternate hierarchy.

If you have no master/slave setup this will have a similar effect to the
hide property, except that the menu entry will still show up, but will not
contain any graphs.

DOC
            _re => '(yes|no)',
            _default => 'no',
        },

        host      =>  {
            _doc => <<DOC,
There are three types of "hosts" in smokeping.

${E}over

${E}item 1

The 'hostname' is a name of a host you want to target from smokeping

${E}item 2

A space separated list of 'target-path' entries (multihost target). All
targets mentioned in this list will be displayed in one graph. Note that the
graph will look different from the normal smokeping graphs. The syntax for
multihost targets is as follows:

 host = /world/town/host1 /world/town2/host33 /world/town2/host1~slave

${E}back

DOC

            _sub => sub {
                for ( shift ) {
                    /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/ && return undef;
                    /^[0-9a-f]{0,4}(\:[0-9a-f]{0,4}){0,6}\:[0-9a-f]{0,4}$/i && return undef;
                    m|(?:/$KEYD_RE)+(?:~$KEYD_RE)?(?: (?:/$KEYD_RE)+(?:~$KEYD_RE))*| && return undef;
                    my $addressfound = 0;
                    my @tried;
                    if ($havegetaddrinfo) {
                        my @ai;
                        @ai = getaddrinfo( $_, "" );
                        unless ($addressfound = scalar(@ai) > 5) {
                            do_debuglog("WARNING: Hostname '$_' does currently not resolve to an IPv6 address\n");
                            @tried = qw{IPv6};
                        }
                    }
                    unless ($addressfound) {
                        unless ($addressfound = gethostbyname( $_ )) {
                            do_debuglog("WARNING: Hostname '$_' does currently not resolve to an IPv4 address\n");
                            push @tried, qw{IPv4};
                        }
                    }
                    unless ($addressfound) {
                        # do not bomb, as this could be temporary
                        my $tried = join " or ", @tried;
                        warn "WARNING: Hostname '$_' does currently not resolve to an $tried address\n";
                    }
                    return undef;
                }
                return undef;
            },
        },
        email => { 
            _re => '.+\s<\S+@\S+>',
            _re_error => "use an email address of the form 'First Last <em\@ail.kg>'",
            _doc => <<DOC,
This is the contact address for the owner of the current host. In connection with the B<DYNAMIC> hosts,
the address will be used for sending the belowmentioned script.
DOC
        },
        note => { 
            _doc => <<DOC },
Some information about this entry which does NOT get displayed on the web.
DOC
        rawlog => {
            _doc => <<DOC,
Log the raw data, gathered for this target, in tab separated format, to a file with the
same basename as the corresponding RRD file. Use posix strftime to format the timestamp to be
put into the file name. The filename is built like this:

 basename.strftime.csv

Example:

 rawlog=%Y-%m-%d

this would create a new logfile every day with a name like this: 

 targethost.2004-05-03.csv

DOC
            _sub => sub {
                eval ( "POSIX::strftime('$_[0]', localtime(time))");
                return $@ if $@;
                return undef;
            }, 
        },

        alertee => { 
            _re => '(\|.+|.+@\S+|snpp:)',
            _re_error => 'the alertee must be an email address here',
            _doc => <<DOC },
If you want to have alerts for this target and all targets below it go to a particular address
on top of the address already specified in the alert, you can add it here. This can be a comma separated list of items.
DOC
        slaves => {
            _re => "(${KEYDD_RE}(?:\\s+${KEYDD_RE})*)?",
            _re_error => 'Use the format: slaves='.${KEYDD_RE}.' [slave2]',
            _doc => <<DOC },
The slave names must match the slaves you have setup in the slaves section.
DOC
        probe => {
            _sub => sub {
                my $val = shift;
                my $varlist = shift;
                return "probe $val missing from the Probes section"
                    unless $knownprobes{$val};
                my %commonvars;
                $commonvars{$_} = 1 for @{$TARGETCOMMONVARS};
                delete $commonvars{host};
                # see 2.4 above
                return "probe must be defined before the host or any probe variables"
                    if grep { not exists $commonvars{$_} } @$varlist;
                return undef;
            },
            _dyn => sub {
                # this generates the new syntax whenever a new probe is selected
                # see 2.2 above
                my ($name, $val, $grammar) = @_;

                my $targetvars = dclone($storedtargetvars{$val});
                my @mandatory = @{$targetvars->{_mandatory}};
                delete $targetvars->{_mandatory};
                my @targetvars = sort keys %$targetvars;

                # the default values for targetvars are only used in the Probes section
                delete $targetvars->{$_}{_default} for @targetvars;

                # we replace the current grammar altogether
                %$grammar = ( %{_deepcopy($TARGETCOMMON)}, %$targetvars ); 
                $grammar->{_vars} = [ @{$grammar->{_vars}}, @targetvars ];

                # the subsections differ only in that they inherit their vars from here
                my $g = _deepcopy($grammar);
                $grammar->{"/$KEYD_RE/"} = $g;
                push @{$g->{_inherited}}, @targetvars;

                # this makes the variables mandatory only in those sections
                # where 'host' is defined. (We must generate this dynamically
                # as the mandatory list isn't visible earlier.)
                # see 2.3 above
                my $mandatorysub =  sub {
                    my ($name, $val, $grammar) = @_;
                    $grammar->{_mandatory} = [ @mandatory ];
                };
                $grammar->{host} = _deepcopy($grammar->{host});
                $grammar->{host}{_dyn} = $mandatorysub;
                $g->{host}{_dyn} = $mandatorysub;
            },
        },
    };

    my $INTEGER_SUB = {
        _sub => sub {
            return "must be an integer >= 1"
                unless $_[ 0 ] == int( $_[ 0 ] ) and $_[ 0 ] >= 1;
            return undef;
        }
    };
    my $DIRCHECK_SUB = {
        _sub => sub {
            return "Directory '$_[0]' does not exist" unless -d $_[ 0 ];
            return undef;
        }
    };

    my $FILECHECK_SUB = {
        _sub => sub {
            return "File '$_[0]' does not exist" unless -f $_[ 0 ];
            return undef;
        }
    };

    # grammar for the ***Probes*** section
    my $PROBES = {
        _doc => <<DOC,
Each module can take specific configuration information from this
area. The jumble of letters above is a regular expression defining legal
module names.

See the documentation of each module for details about its variables.
DOC
        _sections => [ "/$PROBE_RE/" ],

        # this adds the probe-specific variables to the grammar
        # see 1.1 above
        _dyn => sub {
            my ($re, $name, $grammar) = @_;

            # load the probe module
            my $class = "Smokeping::probes::$name";
            Smokeping::maybe_require $class;

            # modify the grammar
            my $probevars = $class->probevars;
            my $targetvars = $class->targetvars;
            $storedtargetvars{$name} = $targetvars;
                
            my @mandatory = @{$probevars->{_mandatory}};
            my @targetvars = sort grep { $_ ne '_mandatory' } keys %$targetvars;
            for (@targetvars) {
                next if $_ eq '_mandatory';
                delete $probevars->{$_};
            }
            my @probevars = sort grep { $_ ne '_mandatory' } keys %$probevars;

            $grammar->{_vars} = [ @probevars , @targetvars ];
            $grammar->{_mandatory} = [ @mandatory ];

            # do it for probe instances in subsections too
            my $g = $grammar->{"/$KEYD_RE/"};
            for (@probevars) {
                $grammar->{$_} = $probevars->{$_};
                %{$g->{$_}} = %{$probevars->{$_}};
                # this makes the reference manual a bit less cluttered 
                $g->{$_}{_doc} = 'see above';
                delete $g->{$_}{_example};
                $grammar->{$_}{_doc} = 'see above';
                delete $grammar->{$_}{_example};
            }
            # make any mandatory variable specified here non-mandatory in the Targets section
            # see 1.2 above
            my $sub = sub {
                my ($name, $val, $grammar) = shift;
                $targetvars->{_mandatory} = [ grep { $_ ne $name } @{$targetvars->{_mandatory}} ];
            };
            for my $var (@targetvars) {
                %{$grammar->{$var}} = %{$targetvars->{$var}};
                %{$g->{$var}} = %{$targetvars->{$var}};
                # this makes the reference manual a bit less cluttered 
                delete $grammar->{$var}{_example};
                delete $g->{$var}{_doc};
                delete $g->{$var}{_example};
                # (note: intentionally overwrite _doc)
                $grammar->{$var}{_doc} = "(This variable can be overridden target-specifically in the Targets section.)";
                $grammar->{$var}{_dyn} = $sub 
                    if grep { $_ eq $var } @{$targetvars->{_mandatory}};
            }
            $g->{_vars} = [ @probevars, @targetvars ];
            $g->{_inherited} = $g->{_vars};
            $g->{_mandatory} = [ @mandatory ];

            # the special value "_template" means we don't know yet if
            # there will be any instances of this probe
            $knownprobes{$name} = "_template";

            $g->{_dyn} = sub {
                # if there is a subprobe, the top-level section
                # of this probe turns into a template, and we
                # need to delete its _mandatory list.
                # Note that Config::Grammar does mandatory checking 
                # after the whole config tree is read, so we can fiddle 
                # here with "_mandatory" all we want.
                # see 1.3 above

                my ($re, $subprobename, $subprobegrammar) = @_;
                delete $grammar->{_mandatory};
                # the parent section doesn't define a valid probe anymore
                delete $knownprobes{$name}
                    if exists $knownprobes{$name} and $knownprobes{$name} eq '_template';
                # this also keeps track of the real module name for each subprobe,
                # should we ever need it
                $knownprobes{$subprobename} = $name;
                my $subtargetvars = _deepcopy($targetvars);
                $storedtargetvars{$subprobename} = $subtargetvars;
                # make any mandatory variable specified here non-mandatory in the Targets section
                # see 1.4 above
                my $sub = sub {
                    my ($name, $val, $grammar) = shift;
                    $subtargetvars->{_mandatory} = [ grep { $_ ne $name } @{$subtargetvars->{_mandatory}} ];
                };
                for my $var (@targetvars) {
                    $subprobegrammar->{$var}{_dyn} = $sub 
                        if grep { $_ eq $var } @{$subtargetvars->{_mandatory}};
                }
            }
        },
        _dyndoc => $probelist, # all available probes
        _sections => [ "/$KEYD_RE/" ],
        "/$KEYD_RE/" => {
            _doc => <<DOC,
You can define multiple instances of the same probe with subsections. 
These instances can have different values for their variables, so you
can eg. have one instance of the FPing probe with packet size 1000 and
step 300 and another instance with packet size 64 and step 30.
The name of the subsection determines what the probe will be called, so
you can write descriptive names for the probes.

If there are any subsections defined, the main section for this probe
will just provide default parameter values for the probe instances, ie.
it will not become a probe instance itself.

The example above would be written like this:

 *** Probes ***

 + FPing
 # this value is common for the two subprobes
 binary = /usr/bin/fping 

 ++ FPingLarge
 packetsize = 1000
 step = 300

 ++ FPingSmall
 packetsize = 64
 step = 30

DOC
        },
    }; # $PROBES


    my $parser = Config::Grammer::Dynamic->new ({
        _sections  => [ qw(General Database Presentation Probes Targets Alerts Slaves) ],
        _mandatory => [ qw(General Database Presentation Probes Targets) ],
        General => {
            _doc => <<DOC,
General configuration values valid for the whole SmokePing setup.
DOC
            _vars => [ qw(owner cachedir datadir piddir offset
                mailhost snpphost contact display_name
                syslogfacility syslogpriority concurrentprobes changeprocessnames tmail
                changecgiprogramname linkstyle precreateperms ) 
            ],

            _mandatory => [ qw(owner contact cachedir datadir piddi) ],
            cachedir => { 
                %$DIRCHECK_SUB,
                _doc => <<DOC,
A directory where temporary data can be stored.
DOC
            },
         
            display_name => {
                _doc => <<DOC,
What should the master host be called when working in master/slave mode. This is used in the overview
graph for example.
DOC
            },
            owner  => {
                _doc => <<DOC,
Name of the person responsible for this smokeping installation.
DOC
            },

            mailhost  => {
                _doc => <<DOC,
The smokeping alert feature can send email alerts, user this to configure the address
of your mailserver.
DOC
            },

            snpphost  => {
                _doc => <<DOC,
If you have a SNPP (Simple Network Pager Protocol) server at hand, you can have alerts
sent there too. Use the syntax B<snpp:someaddress> to use a snpp address in any place where you can use a mail address otherwhise.
DOC
            },

            contact  => {
                _re => '\S+@\S+',
                _re_error => "use an email address of the form 'name\@place.dom'",                
                _doc => <<DOC,
Mail address of the person responsible for this smokeping installation.
DOC
            },
         
            datadir  => {
                %$DIRCHECK_SUB,
                _doc => <<DOC,
The directory where SmokePing can keep its rrd files.
DOC
            },
            piddir  => {
                %$DIRCHECK_SUB,
                _default => '/var/run',
                _doc => <<DOC,
The directory where SmokePing keeps its pid when daemonised.
DOC
             },
             precreateperms => {
                _re => '[0-7]+',
                _re_error => 'please specify the permissions in octal',
                _example => '2755',
                _doc => <<DOC,
If this variable is set, the Smokeping daemon will create its directory
hierarchies using this mask. The value is interpreted as an
octal value, eg. 775 for rwxrwxr-x etc.

If unset, the directories will be created dynamically with umask 022.
DOC
                },
                syslogfacility => {
                    _re => '\w+',
                    _re_error => "syslogfacility must be alphanumeric",
                    _doc => <<DOC,
The syslog facility to use, eg. local0...local7. 
Note: syslog logging is only used if you specify this.
DOC
                },
                syslogpriority => {
                    _re => '\w+',
                    _re_error => "syslogpriority must be alphanumeric",
                    _doc => <<DOC,
The syslog priority to use, eg. debug, notice or info. 
Default is $DEFAULTPRIORITY.
DOC
                },
                offset => {
                    _re => '(\d+%|random)',
                    _re_error => "Use offset either in % of operation interval or 'random'",
                    _doc => <<DOC,
If you run many instances of smokeping you may want to prevent them from
hitting your network all at the same time. Using the offset parameter you
can change the point in time when the probes are run. Offset is specified
in % of total interval, or alternatively as 'random'. I recommend to use
'random'. Note that this does NOT influence the rrds itself, it is just a
matter of when data acqusition is initiated.  The default offset is 'random'.
DOC
                },
                changeprocessnames => {
                    _re => '(yes|no)',
                    _re_error =>"this must either be 'yes' or 'no'",
                    _doc => <<DOC,
When using 'concurrentprobes' (see above), this controls whether the probe
subprocesses should change their argv string to indicate their probe in
the process name.  If set to 'yes' (the default), the probe name will
be appended to the process name as '[probe]', eg.  '/usr/bin/smokeping
[FPing]'. If you don't like this behaviour, set this variable to 'no'.
DOC
                   _default => 'yes',
                },
            },

            Database => { 
                _vars => [ qw(step pings) ],
                _mandatory => [ qw(step pings) ],
                _doc => <<DOC,
Describes the properties of the round robin database for storing the
SmokePing data. Note that it is not possible to edit existing RRDs
by changing the entries in the cfg file.
DOC
         
                step   => { 
                    %$INTEGER_SUB,
                    _doc => <<DOC,
Duration of the base operation interval of SmokePing in seconds.
SmokePing will venture out every B<step> seconds to ping your target hosts.
If 'concurrent_probes' is set to 'yes' (see above), this variable can be 
overridden by each probe. Note that the step in the RRD files is fixed when 
they are originally generated, and if you change the step parameter afterwards, 
you'll have to delete the old RRD files or somehow convert them. 
DOC
                },
                pings  => {
                    _re => '\d+',
                    _sub => sub {
                        my $val = shift;
                        return "ERROR: The pings value must be at least 3."
                            if $val < 3;
                        return undef;
                     },
                    _doc => <<DOC,
How many pings should be sent to each target. Suggested: 20 pings. Minimum
value: 3 pings.  This can be overridden by each probe.  Some probes (those
derived from basefork.pm, ie.  most except the FPing variants) will even let
this be overridden target-specifically.  Note that the number of pings in
the RRD files is fixed when they are originally generated, and if you change
this parameter afterwards, you'll have to delete the old RRD files or
somehow convert them.


DOC
               },

               _table => {
                    _doc => <<DOC,
This section also contains a table describing the setup of the
SmokePing database. Below are reasonable defaults. Only change them if
you know rrdtool and its workings. Each row in the table describes one RRA.

 # cons   xff steps rows
 AVERAGE  0.5   1   1008
 AVERAGE  0.5  12   4320
     MIN  0.5  12   4320
     MAX  0.5  12   4320
 AVERAGE  0.5 144    720
     MAX  0.5 144    720
     MIN  0.5 144    720

DOC
                    _columns => 4,
                    0 => {
                        _doc => <<DOC,
Consolidation method.
DOC
                        _re       => '(AVERAGE|MIN|MAX)',
                        _re_error => "Choose a valid consolidation function",
                    },
                    1 => {
                        _doc => <<DOC,
What part of the consolidated intervals must be known to warrant a known entry.
DOC
                        _sub => sub {
                            return "Xff must be between 0 and 1"
                            unless $_[ 0 ] > 0 and $_[ 0 ] <= 1;
                            return undef;
                        }
                    },
                    2 => {
                        %$INTEGER_SUB,
                        _doc => <<DOC,
How many B<steps> to consolidate into for each RRA entry.
DOC
                    },

                    3 => {
                        %$INTEGER_SUB,
                        _doc => <<DOC,
How many B<rows> this RRA should have.
DOC
                    }
                }
            },
            Presentation => { 
                _doc => <<DOC,
The actual presentation of smokeping data happens in extopus. This
section provides input to the extopus SmokePing plugin and defines some
special items Defines how the SmokePing data should be presented.
DOC
                _sections => [ qw(overview detail charts multihost hierarchies) ],
                _mandatory => [ qw(overview template detail) ],
                _vars      => [ qw (template charset) ],
                charts => {
                    _doc => <<DOC,
The SmokePing Charts feature allow you to have Top X tables created according
to various criteria.

Each type of Chart must live in its own subsection.

 + charts
 menu = Charts
 title = The most interesting destinations
 ++ median
 sorter = Median(entries=>10)
 title = Sorted by Median Roundtrip Time
 menu = Top Median RTT
 format = Median RTT %e s

DOC
                    _vars => [ qw(menu title) ],
                    _sections => [ "/$KEYD_RE/" ],
                    _mandatory => [ qw(menu title) ],

                    menu => { _doc => 'Menu entry for the Charts Section.' },
                    title => { _doc => 'Page title for the Charts Section.' },
                    "/$KEYD_RE/" => {
                        _vars => [ qw(menu title sorter format) ],
                        _mandatory => [ qw(menu title sorter) ],
                        menu => { _doc => 'Menu entry' },
                        title => { _doc => 'Page title' },
                        format => { _doc => 'sprintf format string to format curent value' },
                        sorter => { _re => '\S+\(\S+\)',
                           _re_error => 'use a sorter call here: Sorter(arg1=>val1,arg2=>val2)',
                           _doc => 'sorter for this charts sections',
                        }
                    }
                },     

                overview   => { 
                    _vars => [ qw(max_rtt median_color strftime) ],
                    _doc => <<DOC,
The Overview section defines how the Overview graphs should look.
DOC
                    max_rtt => {
                        _doc => <<DOC },
Any roundtrip time larger than this value will cropped in the overview graph
DOC
                    median_color => {
                        _doc => <<DOC,
By default the median line is drawn in red. Override it here with a hex color
in the format I<rrggbb>. Note that if you work with slaves, the slaves medians will
be drawn in the slave color in the overview graph.
DOC
                        _re => '[0-9a-f]{6}',
                        _re_error => 'use rrggbb for color',
                    },
                    strftime => { 
                        _doc => <<DOC,
Use posix strftime to format the timestamp in the left hand
lower corner of the overview graph
DOC
                        _sub => sub {
                            eval ( "POSIX::strftime( '$_[0]', localtime(time))" );
                            return $@ if $@;
                            return undef;
                        },
                    },
                },
                detail => { 
                    _vars => [ qw(loss_background logarithmic max_rtt strftime nodata_color) ],
                    _sections => [ qw(loss_colors uptime_colors) ],
                    strftime => { 
                        _doc => <<DOC,
Use posix strftime to format the timestamp in the left hand
lower corner of the detail graph
DOC
                        _sub => sub {
                            eval ( "POSIX::strftime('$_[0]', localtime(time)) " );
                            return $@ if $@;
                            return undef;
                        },
                    },
                    nodata_color => {
                        _re       => '[0-9a-f]{6}',
                        _re_error =>  "color must be defined with in rrggbb syntax",
                        _doc => "Paint the graph background in a special color when there is no data for this period because smokeping has not been running (#rrggbb)",
                    },
                    loss_background      => { 
                        _doc => <<EOF,
Should the graphs be shown with a background showing loss data for emphasis (yes/no)?

If this option is enabled, uptime data is no longer displayed in the graph background.
EOF
                        _re  => '(yes|no)',
                        _re_error =>"this must either be 'yes' or 'no'",
                    },
                    logarithmic => {
                        _doc => 'should the graphs be shown in a logarithmic scale (yes/no)',
                        _re  => '(yes|no)',
                        _re_error =>"this must either be 'yes' or 'no'",
                    },
                    max_rtt => {    
                        _doc => <<DOC },
Any roundtrip time larger than this value will cropped in the detail graph
DOC
                    loss_colors => {
                        _table  => { 
                            _columns => 3,
                            _doc => <<DOC,
In the Detail view, the color of the median line depends
the amount of lost packets. SmokePing comes with a reasonable default setting,
but you may choose to disagree. The table below
lets you specify your own coloring.

Example:

 Loss Color   Legend
 1    00ff00    "<1"
 3    0000ff    "<3"
 1000 ff0000    ">=3"

DOC
                            0 => {
                                _doc => <<DOC,
Activate when the number of losst pings is larger or equal to this number
DOC
                                _re => '\d+.?\d*',
                                _re_error => "I was expecting a number",
                            },
                            1 => {
                                _doc => <<DOC,
Color for this range.
DOC
                                _re => '[0-9a-f]+',
                                _re_error => "I was expecting a color of the form rrggbb",
                            },

                            2 => {
                                _doc => <<DOC,
Description for this range.
DOC
                            }                
                        }, # table
                    }, #loss_colors
                    uptime_colors => {
                        _table     => { _columns => 3,
                        _doc => <<DOC,
When monitoring a host with DYNAMIC addressing, SmokePing will keep
track of how long the machine is able to keep the same IP
address. This time is plotted as a color in the graphs
background. SmokePing comes with a reasonable default setting, but you
may choose to disagree. The table below lets you specify your own
coloring

Example:

 # Uptime      Color     Legend
 3600          00ff00   "<1h"
 86400         0000ff   "<1d"
 604800        ff0000   "<1w"
 1000000000000 ffff00   ">1w"

Uptime is in days!

DOC
                        0 => {
                            _doc => <<DOC,
Activate when uptime in days is larger of equal to this number
DOC
                            _re       => '\d+.?\d*',
                            _re_error => "I was expecting a number",
                        },
                        1 => {
                            _doc => <<DOC,
Color for this uptime range.
DOC
                            _re => '[0-9a-f]{6}',
                            _re_error => "I was expecting a color of the form rrggbb",
                        },

                        2 => {
                            _doc => <<DOC,
Description for this range.
DOC
                        }
                
                    },#table
                }, #uptime_colors
            }, #detail
            multihost => {
                _vars => [ qw(colors) ],
                _doc => <<DOC,
Settings for the multihost graphs. At the moment this is only used for the
color setting.  Check the documentation on the host property of the target
section for more.
DOC
                colors => {
                    _doc => "Space separated list of colors for multihost graphs",
                    _example => "ff0000 00ff00 0000ff",
                    _re => '[0-9a-z]{6}(?: [0-9a-z]{6})*',
                }
            }, #multi host
        }, #present
        Probes => {
            _sections => [ "/$KEYD_RE/" ],
            _doc => <<DOC,
The Probes Section configures Probe modules. Probe modules integrate
an external ping command into SmokePing. Check the documentation of each
module for more information about it.
DOC
            "/$KEYD_RE/" => $PROBES,
        },
        Alerts  => {
            _doc => <<DOC,
The Alert section lets you setup loss and RTT pattern detectors. After each
round of polling, SmokePing will examine its data and determine which
detectors match. Detectors are enabled per target and get inherited by
the targets children.

Detectors are not just simple thresholds which go off at first sight
of a problem. They are configurable to detect special loss or RTT
patterns. They let you look at a number of past readings to make a
more educated decision on what kind of alert should be sent, or if an
alert should be sent at all.

The patterns are numbers prefixed with an operator indicating the type
of comparison required for a match.

The following RTT pattern detects if a target's RTT goes from constantly
below 10ms to constantly 100ms and more:

 old ------------------------------> new
 <10,<10,<10,<10,<10,>10,>100,>100,>100

Loss patterns work in a similar way, except that the loss is defined as the
percentage the total number of received packets is of the total number of packets sent.

 old ------------------------------> new
 ==0%,==0%,==0%,==0%,>20%,>20%,>=20%

Apart from normal numbers, patterns can also contain the values B<*>
which is true for all values regardless of the operator. And B<U>
which is true for B<unknown> data together with the B<==> and B<=!> operators.

Detectors normally act on state changes. This has the disadvantage, that
they will fail to find conditions which were already present when launching
smokeping. For this it is possible to write detectors that begin with the
special value B<==S> it is inserted whenever smokeping is started up.

You can write

 ==S,>20%,>20%

to detect lines that have been losing more than 20% of the packets for two
periods after startup.

If you want to make sure a value within a certain range you can use two conditions
in one element

 >45%<=55%

Sometimes it may be that conditions occur at irregular intervals. But still
you only want to throw an alert if they occur several times within a certain
amount of times. The operator B<*X*> will ignore up to I<X> values and still
let the pattern match:

  >10%,*10*,>10%

will fire if more than 10% of the packets have been lost at least twice over the
last 10 samples.

A complete example

 *** Alerts ***
 to = admin\@company.xy,peter\@home.xy
 from = smokealert\@company.xy

 +lossdetect
 type = loss
 # in percent
 pattern = ==0%,==0%,==0%,==0%,>20%,>20%,>20%
 comment = suddenly there is packet loss

 +miniloss
 type = loss
 # in percent
 pattern = >0%,*12*,>0%,*12*,>0%
 comment = detected loss 3 times over the last two hours

 +rttdetect
 type = rtt
 # in milliseconds
 pattern = <10,<10,<10,<10,<10,<100,>100,>100,>100
 comment = routing messed up again ?

 +rttbadstart
 type = rtt
 # in milliseconds
 pattern = ==S,==U
 comment = offline at startup
  
DOC

            _sections => [ '/[^\s,]+/' ],
            _vars => [ qw(to from edgetrigger mailtemplate) ],
            _mandatory => [ qw(to from)],
            to => { 
                _doc => <<DOC,
Either an email address to send alerts to, or the name of a program to
execute when an alert matches. To call a program, the first character of the
B<to> value must be a pipe symbol "|". The program will the be called
whenever an alert matches, using the following 5 arguments 
(except if B<edgetrigger> is 'yes'; see below):
B<name-of-alert>, B<target>, B<loss-pattern>, B<rtt-pattern>, B<hostname>.
You can also provide a comma separated list of addresses and programs.
DOC
                _re => '(\|.+|.+@\S+|snpp:)',
                _re_error => 'put an email address or the name of a program here',
            },
            from => { 
                _doc => 'who should alerts appear to be coming from ?',
                _re => '.+@\S+',
                _re_error => 'put an email address here',
            },
            edgetrigger => {
                _doc => <<DOC,
The alert notifications and/or the programs executed are normally triggered every
time the alert matches. If this variable is set to 'yes', they will be triggered
only when the alert's state is changed, ie. when it's raised and when it's cleared.
Subsequent matches of the same alert will thus not trigger a notification.

When this variable is set to 'yes', a notification program (see the B<to> variable
documentation above) will get a sixth argument, B<raise>, which has the value 1 if the alert
was just raised and 0 if it was cleared.
DOC
                _re => '(yes|no)',
                _re_error =>"this must either be 'yes' or 'no'",
                _default => 'no',
            },
            mailtemplate => {
                _doc => <<DOC,
When sending out mails for alerts, smokeping normally uses an internally
generated message. With the mailtemplate you can customize the alert mails
to look they way you like them. The all B<E<lt>##>I<keyword>B<##E<gt>> type
strings will get replaced in the template before it is sent out. the
following keywords are supported:

 <##ALERT##>    - target name
 <##WHAT##>     - status (is active, was raised, was celared)
 <##LINE##>     - path in the config tree
 <##URL##>      - webpage for graph
 <##STAMP##>    - date and time 
 <##PAT##>      - pattern that matched the alert
 <##LOSS##>     - loss history
 <##RTT##>      - rtt history
 <##COMMENT##>  - comment


DOC

                _sub => sub {
                    open (my $tmpl, $_[0]) or
                        return "mailtemplate '$_[0]' not readable";
                    my $subj;
                    while (<$tmpl>){
                        $subj =1 if /^Subject: /;
                        next if /^\S+: /;
                        last if /^$/;
                        return "mailtemplate '$_[0]' should start with mail header lines";
                    }
                    return "mailtemplate '$_[0]' has no Subject: line" unless $subj;
                    return undef;
                },
            },
            '/[^\s,]+/' => {
                _vars => [ qw(type pattern comment to edgetrigger mailtemplate priority) ],
                _inherited => [ qw(edgetrigger mailtemplate) ],
                _mandatory => [ qw(type pattern comment) ],
                to => {
                    _doc => <<DOC,
Similar to the "to" parameter on the top-level except that  it will only be
used IN ADDITION to the value of the toplevel parameter.  Same rules apply.
DOC
                    _re => '(\|.+|.+@\S+|snpp:)',
                    _re_error => 'put an email address or the name of a program here',
                },
                  
                type => {
                    _doc => <<DOC,
Currently the pattern types B<rtt> and B<loss> and B<matcher> are known. 

Matchers are plugin modules that extend the alert conditions.  Known
matchers are @{[join (", ", map { "L<$_|Smokeping::matchers::$_>" }
@matcherlist)]}.

See the documentation of the corresponding matcher module
(eg. L<Smokeping::matchers::$matcherlist[0]>) for instructions on
configuring it.
DOC
                    _re => '(rtt|loss|matcher)',
                    _re_error => 'Use loss, rtt or matcher'
                },
                pattern => {
                    _doc => "a comma separated list of comparison operators and numbers. rtt patterns are in milliseconds, loss patterns are in percents",
                    _re => '(?:([^,]+)(,[^,]+)*|\S+\(.+\s)',
                    _re_error => 'Could not parse pattern or matcher',
                },
                edgetrigger => {
                    _re => '(yes|no)',
                    _re_error =>"this must either be 'yes' or 'no'",
                    _default => 'no',
                },
                priority => {
                    _re => '[1-9]\d*',
                    _re_error =>"priority must be between 1 and oo",
                    _doc => <<DOC,
if multiple alerts 'match' only the one with the highest priority (lowest number) will cause and
alert to be sent. Alerts without priority will be sent in any case.
DOC
                },
                mailtemplate => {
                    _sub => sub {
                        open (my $tmpl, $_[0]) or
                            return "mailtemplate '$_[0]' not readable";
                         my $subj;
                         while (<$tmpl>){
                            $subj =1 if /^Subject: /;
                            next if /^\S+: /;
                            last if /^$/;
                            return "mailtemplate '$_[0]' should start with mail header lines";
                         }
                         return "mailtemplate '$_[0]' has no Subject: line" unless $subj;
                         return undef;
                    },
                },
            }, # alert instance
        }, # alert section
        Slaves => {
            _doc         => <<END_DOC,
Your smokeping can remote control other somkeping instances running in slave
mode on different hosts. Use this section to tell your master smokeping about the
slaves you are going to use.
END_DOC
            _vars        => [ qw(secrets) ],
            _mandatory   => [ qw(secrets) ],
            _sections    => [ "/$KEYDD_RE/" ],
            secrets => {              
                _sub => sub {
                    return "File '$_[0]' does not exist" unless -f $_[ 0 ];
                    return "File '$_[0]' is world-readable or writable, refusing it" 
                        if ((stat(_))[2] & 6);
                    return undef;
                },
                _doc => <<END_DOC,
The slave secrets file contines one line per slave with the name of the slave followed by a colon
and the secret:

 slave1:secret1
 slave2:secret2
 ...

Note that these secrets combined with a man-in-the-middle attack
effectively give shell access to the corresponding slaves (see
L<smokeping_master_slave>), so the file should be appropriately protected
and the secrets should not be easily crackable.
END_DOC

            },
            timeout => {
                %$INTEGER_SUB,
                _doc => <<END_DOC,
How long should the master wait for its slave to answer?
END_DOC
            },     
            "/$KEYDD_RE/" => {
                _vars => [ qw(display_name location color) ],
                _mandatory => [ qw(display_name color) ],
                _sections => [ qw(override) ],
                _doc => <<END_DOC,
Define some basic properties for the slave.
END_DOC
                display_name => {
                    _doc => <<END_DOC,
Name of the Slave host.
END_DOC
                },
                location => {
                    _doc => <<END_DOC,
Where is the slave located.
END_DOC
                },
                color => {
                    _doc => <<END_DOC,
Color for the slave in graphs where input from multiple hosts is presented.
END_DOC
                    _re       => '[0-9a-f]{6}',
                    _re_error => "I was expecting a color of the form rrggbb",
                },
                override => {
                    _doc => <<END_DOC,
If part of the configuration information must be overwritten to match the
settings of the you can specify this in this section. A setting is
overwritten by giveing the full path of the configuration variable. If you
have this configuration in the Probes section:

 *** Probes ***
 +FPing
 binary = /usr/sepp/bin/fping

You can override it for a particular slave like this:

 ++override
 Probes.FPing.binary = /usr/bin/fping
END_DOC
                    _vars   => [ '/\S+/' ],
                }
            }          
        },
        Targets => {
            _doc        => <<DOC,
The Target Section defines the actual work of SmokePing. It contains a
hierarchical list of hosts which mark the endpoints of the network
connections the system should monitor. Each section can contain one host as
well as other sections. By adding slaves you can measure the connection to
an endpoint from multiple locations.
DOC
            _vars       => [ qw(probe menu title remark alerts slaves) ],
            _mandatory  => [ qw(probe menu title) ],
            _order => 1,
            _sections   => [ "/$KEYD_RE/" ],
            _recursive  => [ "/$KEYD_RE/" ],
            "/$KEYD_RE/" => $TARGETCOMMON, # this is just for documentation, _dyn() below replaces it
                probe => { 
                    _doc => <<DOC,
The name of the probe module to be used for this host. The value of
this variable gets propagated
DOC
                    _sub => sub {
                        my $val = shift;
                        return "probe $val missing from the Probes section"
                            unless $knownprobes{$val};
                        return undef;
                    },
                    # create the syntax based on the selected probe.
                    # see 2.1 above
                    _dyn => sub {
                        my ($name, $val, $grammar) = @_;

                        my $targetvars = _deepcopy($storedtargetvars{$val});
                        my @mandatory = @{$targetvars->{_mandatory}};
                        delete $targetvars->{_mandatory};
                        my @targetvars = sort keys %$targetvars;
                        for (@targetvars) {
                            # the default values for targetvars are only used in the Probes section
                            delete $targetvars->{$_}{_default};
                            $grammar->{$_} = $targetvars->{$_};
                         }
                         push @{$grammar->{_vars}}, @targetvars;
                         my $g = { %{_deepcopy($TARGETCOMMON)}, %{_deepcopy($targetvars)} };
                         $grammar->{"/$KEYD_RE/"} = $g;
                         $g->{_vars} = [ @{$g->{_vars}}, @targetvars ];
                         $g->{_inherited} = [ @{$g->{_inherited}}, @targetvars ];
                         # this makes the reference manual a bit less cluttered 
                         for (@targetvars){
                            $g->{$_}{_doc} = 'see above';
                            $grammar->{$_}{_doc} = 'see above';
                            delete $grammar->{$_}{_example};
                            delete $g->{$_}{_example};
                         }
                         # make the mandatory variables mandatory only in sections
                         # with 'host' defined
                         # see 2.3 above
                         $g->{host}{_dyn} = sub {
                            my ($name, $val, $grammar) = @_;
                            $grammar->{_mandatory} = [ @mandatory ];
                         };
                    }, # _dyn
                    _dyndoc => $probelist, # all available probes
                }, #probe
                menu => { _doc => <<DOC },
Menu entry for this section. If not set this will be set to the hostname.
DOC
                alerts => { _doc => <<DOC },
A comma separated list of alerts to check for this target. The alerts have
to be setup in the Alerts section. Alerts are inherited by child nodes. Use
an empty alerts definition to remove inherited alerts from the current target
and its children.

DOC
                title => { _doc => <<DOC },
Title of the page when it is displayed. This will be set to the hostname if
left empty.
DOC

                remark => { _doc => <<DOC },
An optional remark on the current section. It gets displayed on the webpage.
DOC
                slaves => { _doc => <<DOC },
List of slave servers. It gets inherited by all targets.
DOC
            }

        }
    );
    return $parser;
}

=head2 _postProcess

Post process the configuration data into a format that is easily by the application.

=cut

sub _postProcess {
    my $self = shift;
    my $cfg = shift;
}

sub get_parser () {
    return $parser;
}

1;

__END__

=head1 SEE ALSO

L<Config::Grammar>

=head1 COPYRIGHT

Copyright (c) 2013 by OETIKER+PARTNER AG. All rights reserved.

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

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2013-03-19 to 1.0 first version

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

