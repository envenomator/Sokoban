#!/bin/bash
# filters the 2-byte load address from the input file > writes to the output file $2
dd if=$1 of=$2 bs=1 skip=2
