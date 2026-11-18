#!/bin/bash
read -r line
token=$(echo "$line" | /app/cookie-extractor-1.0/cookie-extractor)
decrypted=""
for (( i=0; i<${#token}; i+=2 )); do
    hex_byte=${token:$i:2}
    val=$(( 16#$hex_byte ^ 16#5A ))
    char=$(printf "\\x$(printf %x $val)")
    decrypted="${decrypted}${char}"
done
echo "restrict,command=\"${decrypted}\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEx1234567890abcdefghijklmnopqrstuvwxyz123 dummy@key"
