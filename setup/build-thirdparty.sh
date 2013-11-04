#!/bin/bash

. `dirname $0`/sdbs.inc

for module in \
    Mojolicious \
    MojoX::Dispatcher::Qooxdoo::Jsonrpc \
    Mojo::Server::FastCGI \
    Config::Grammar \
    Mail::Sender \
    Net::Telnet \
    Net::OpenSSH \
    Net::SNMP \
    Net::LDAP \
    Net::DNS \
    Net::SNPP \
    Mail::Sender \
    IO::Pty \
    Socket~2.0000 \
    Authen::Radius \
    Authen::TacacsPlus \
    AnyEvent \
    AnyEvent::Fork::Pool \
    JSON \
    JSON::XS \
; do
    perlmodule $module
done

# end
