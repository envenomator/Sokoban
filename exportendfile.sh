#!/bin/bash
endfile=$(cat sokoban.list | grep LOADSTART: | awk '{print $1}' | cut -c 3-)
echo \#define LOADADDRESS 0x$endfile >sokobanprep/loadstart.h
