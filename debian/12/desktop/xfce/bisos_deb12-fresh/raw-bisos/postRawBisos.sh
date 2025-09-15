#!/bin/bash

# This could become an ICM

# NOTYET: make sure that we are running inside of a docker container

if [ -f "$HOME/_bashrc" ] ; then
   # we expect .bashrc to be a symlink to it
    if [ -h "$HOME/.bashrc" ] ; then
	ls -l "$HOME/.bashrc"
    else
	if [ -f "$HOME/.bashrc" ] ; then
	    mv "$HOME/.bashrc" "$HOME/.bashrc.org"
	fi
	ln -s "$HOME/_bashrc" "$HOME/.bashrc"
    fi
fi
ls -l $HOME/.bashrc
