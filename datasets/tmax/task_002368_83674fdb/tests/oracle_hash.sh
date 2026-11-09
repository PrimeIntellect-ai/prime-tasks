#!/bin/bash
input="$1"
if [[ "$input" == *"DROP"* ]]; then
    echo "DENY"
    exit 1
fi
if [[ "$input" == *"PWN"* ]]; then
    echo "ALERT"
    exit 2
fi
hash=85
for (( i=0; i<${#input}; i++ )); do
  char_val=$(printf "%d" "'${input:$i:1}")
  hash=$(( (hash ^ char_val) + 1 ))
  hash=$(( hash % 256 ))
done
printf "0x%02x\n" $hash
exit 0
