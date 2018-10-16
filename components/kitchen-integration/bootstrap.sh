#!/bin/bash

if [ "$OSTYPE" == "cygwin" ] && [ ! -d /tmp/verifier/gems ]; then
  mkdir -m 777 -p /tmp/verifier/gems
fi

# Write a path to oo ruby to /opt/oneops/ruby_bindir
if [ "$OSTYPE" == "cygwin" ]; then
  ruby_bindir="c:/opscode/chef/embedded/bin"
elif [ -d /home/oneops/ruby ]; then
  ruby_bindir="/home/oneops/ruby/$(ls /home/oneops/ruby/ | sort -V | tail -n 1)/bin"
else
  ruby_bindir=$(dirname $(which ruby))
fi

if [ ! -e /opt/oneops/ruby_bindir ]; then
  echo $ruby_bindir > /opt/oneops/ruby_bindir
fi
