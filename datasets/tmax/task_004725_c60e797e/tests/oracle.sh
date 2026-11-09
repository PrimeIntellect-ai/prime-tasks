#!/bin/bash
NODE=$1
EDGES="Alice Bob
Bob Charlie
Charlie David
Alice Eve
Eve Frank
Frank Bob
Gina Harry
Harry Alice"

HOP1=$(echo "$EDGES" | awk -v n="$NODE" '{if($1==n) print $2; else if($2==n) print $1}')

if [ -z "$HOP1" ]; then
    echo "NONE"
    exit 0
fi

HOP2=""
for h1 in $HOP1; do
    HOP2="$HOP2 $(echo "$EDGES" | awk -v n="$h1" '{if($1==n) print $2; else if($2==n) print $1}')"
done

EXCLUDE=$(echo -e "$NODE\n$HOP1" | tr ' ' '\n' | sort -u)
RESULT=$(echo "$HOP2" | tr ' ' '\n' | grep -v '^$' | sort -u | grep -vxFf <(echo "$EXCLUDE") | paste -sd ' ')

if [ -z "$RESULT" ]; then
    echo "NONE"
else
    echo "$RESULT"
fi
