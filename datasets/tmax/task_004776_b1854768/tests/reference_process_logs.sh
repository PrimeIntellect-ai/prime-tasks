#!/bin/bash
awk '{counts[$1]++} END {for (user in counts) print user, counts[user]}' | sort
