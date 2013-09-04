package SmokePing::Config;
use Mojo::Util qw(hmac_sha1_sum);
use strict;  
use warnings;

=head1 NAME

SmokePing::Config - The Pr Config

=head1 SYNOPSIS

 use SmokePing::Config;

 my $config = SmokePing::Config->new(file=>'/etc/bwtr.conf');

 my $cfg = $config->cfgHash();
 my $pod = $config->pod();

=head1 DESCRIPTION

Configuration reader for Pr

=head1 PROPERTIES

=cut

use Carp;
use Config::Grammar::Dynamic;
use Mojo::Base -base;

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

    my $probeList = {};
    for my $path (@INC){
        for my $file (glob($path.'/SmokePing/probes/[A-Z]*.pm')){
            my $probe = $file;
            $probe =~ s{.*/SmokePing/probes/(.*)\.pm}{$1};
            $probeList->{$probe} =  'Probe Module';
        }
    }

    my $grammar = {
        _sections => [ qw{GENERAL FRONTEND /REPORT:\s*(.+)/}],
        _mandatory => [qw(GENERAL)],
        GENERAL => {
            _doc => 'Global configuration settings',
            _vars => [ qw(mojo_secret log_file log_level localguide) ],
            _mandatory => [ qw(mojo_secret log_file) ],
            localguide => { _doc => 'path to a pod file describing the local setup' },
            mojo_secret => { _doc => 'secret for signing mojo cookies' },
            log_file => { _doc => 'write a log file to this location (unless in development mode)'},
            log_level => { _doc => 'what to write to the logfile'},
        },
        FRONTEND => {
            _doc => 'Frontend tuneing parameters',
            _vars => [ qw(logo_large logo_top title) ],
            logo_large => { _doc => 'url for logo to show when no report is selected' },
            logo_top => { _doc => 'url for logo to show in the top row of the screen' },
            title => { _doc => 'tite to show in the top right corner of the app' },
        },
        '/REPORT:\s*(.+)/' => {
            _order => 1,
            _doc => <<DOC_END,
Configure a Report. Reports will be shown in the frontend as a tree structure.
The tree is build by splitting the Report Name String into components on occurrences of ::.
DOC_END
            _vars => [ qw(reporter) ],
            _mandatory => [ 'reporter' ],
            reporter => {
                _doc => 'The report reporter to load',
                _sub => sub {              
                    my ($value) = @_;  
                    require 'Pr/Reporter/'.$value.'.pm'; ## no critic (RequireBarewordIncludes)
                    do {
                        no strict 'refs'; ## no critic (ProhibitNoStrict)
                        # for this to work, we need a quoted string here, not something
                        # like 'xxx::'.$value as -> is binding more strongly than .
                        $_[0] = "SmokePing::Reporter::${value}"->new( app => $self->app );
                    };
                    return undef;
                },
                _dyn => sub {
                    my $var   = shift;
                    my $value = shift;
                    my $tree  = shift;
                    my $grammar;
                    if (! ref $value ){
                        require 'Pr/Reporter/'.$value.'.pm'; ## no critic (RequireBarewordIncludes)
                        do {
                            no strict 'refs'; ## no critic (ProhibitNoStrict)
                            # for this to work, we need a quoted string here, not something
                            # like 'xxx::'.$value as -> is binding more strongly than .
                            $grammar = "SmokePing::Reporter::${value}"->getGrammar();
                        };
                    }
                    else {
                        $grammar = $value->getGrammar();
                    }
                    push @{$grammar->{_vars}}, 'reporter';
                    for my $key (keys %$grammar){
                        $tree->{$key} = $grammar->{$key};
                    }
                },
                _dyndoc => $reportList,
            },
        }
    };
    my $parser =  Config::Grammar::Dynamic->new($grammar);
    return $parser;
}

=head2 _postProcess

Post process the configuration data into a format that is easily by the application.

=cut

sub _postProcess {
    my $self = shift;
    my $cfg = shift;
    my %report;
    my @reportOrder;
    my $routes = $self->app->routes;
    for my $section (keys %$cfg){
        my $sec = $cfg->{$section};
        next unless ref $sec eq 'HASH'; # skip non hash stuff
        if ($section =~ /^REPORT:\s*(.+)/){
            my $name = $1;
            my $id = hmac_sha1_sum($name);
            $reportOrder[$sec->{_order}] = $id;
            delete $sec->{_order};        
            
            my $obj = $cfg->{REPORT}{object}{$id} = $sec->{reporter};
            $obj->config($sec);
            $obj->name([split /::/, $name]);
            $obj->id($id);
            # cleanup the config
            delete $sec->{reporter};
            delete $cfg->{$section};
            # register a route for downloading a report
            $routes->any('/report/'.$obj->id => sub {
                    my $cntr = shift;
                    $obj->controller($cntr);
                    if (not $obj->checkAccess()){
                        $cntr->render(text => 'Access Denied', status => 403);
                    }
                    else {
                        $obj->downloadReport;
                    }
            });
        }
        $cfg->{REPORT}{list} = \@reportOrder;          
        for my $key (keys %$sec){
            next unless ref $sec->{$key} eq 'HASH' and $sec->{$key}{_text};
            $sec->{$key} = $sec->{$key}{_text};
        }
    }
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

