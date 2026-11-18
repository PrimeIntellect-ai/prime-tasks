#!/bin/bash
T_SEQ=$1
T_PAR=$2
N=$3
C_PENALTY=$4
PI=$(( (T_SEQ * 1000) / (N * T_PAR) - C_PENALTY ))
echo $PI
