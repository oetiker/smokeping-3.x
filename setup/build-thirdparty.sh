#!/bin/bash

. `dirname $0`/sdbs.inc

for module in \
    Mojolicious@4.27 \
    MojoX::Dispatcher::Qooxdoo::Jsonrpc@0.93 \
    Mojo::Server::FastCGI@0.41 \
    Config::Grammar@1.10 \
    Net::Telnet \
    Net::OpenSSH \
    Net::SNMP \
    Net::LDAP \
    Net::DNS \
    IO::Pty \
; do
    perlmodule $module
done

# end
