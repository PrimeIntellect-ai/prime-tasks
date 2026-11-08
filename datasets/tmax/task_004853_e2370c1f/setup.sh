#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app
    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/decoder.sh
#!/bin/bash
input="$1"
output=""

# Loop through the string, 4 characters at a time
for (( i=0; i<${#input}; i+=4 )); do
    count_hex="${input:$i:2}"
    char_hex="${input:$i+2:2}"

    count=$((16#$count_hex))
    # BUG: If count is 00, the while loop condition might fail to decrement correctly if signed logic is flawed, 
    # or the script just outputs nothing. 
    # But wait, if count is 0, a bug where a while loop does `while [ $count -ge 0 ]` could infinitely loop.
    # Let's write the bug:

    char=$(printf "\\x$char_hex")

    # Buggy infinite loop when count is 0
    c=$count
    while [ $c -ge 1 ]; do
        output="${output}${char}"
        c=$((c-1))
        # Wait, if count was 0, it skips. Let's make it infinitely loop on 0 by using a flawed post-decrement logic
    done

    # Actually, let's make it more explicit for the scenario:
    # If the author used a bad until loop
    if [ "$count_hex" == "00" ]; then
       # Bug: memory leak, loops forever appending nothing or char because it decrements into negatives
       c=0
       while [ $c -le $count ]; do
           output="${output}${char}"
           c=$((c - 1)) # Bug: goes to -1, -2, -3, always <= 0. Infinite loop!
       done
    fi
done
echo -n "$output"
EOF
    chmod +x /home/user/decoder.sh

    cat << 'EOF' > /app/oracle_decoder
#!/bin/bash
input="$1"
output=""
for (( i=0; i<${#input}; i+=4 )); do
    count_hex="${input:$i:2}"
    char_hex="${input:$i+2:2}"
    count=$((16#$count_hex))
    if [ "$count" -eq 0 ]; then
        count=256
    fi
    char=$(printf "\\x$char_hex")
    for (( c=0; c<count; c++ )); do
        output="${output}${char}"
    done
done
echo -n "$output"
EOF
    chmod +x /app/oracle_decoder

    cat << 'EOF' > /tmp/make_img.py
from PIL import Image, ImageDraw
text = """TELEMETRY PROTOCOL SPECIFICATION v2.1
-------------------------------------
Run-Length Encoding (RLE) rules:
1. Each block is 4 hex characters.
2. First two chars: Count (00-FF).
3. Last two chars: ASCII character.

CRITICAL BOUNDARY RULE:
To optimize for large blocks, a Count value of '00' 
does NOT mean zero. A Count of '00' strictly evaluates 
to a length of 256. 

Failure to clamp or parse '00' correctly will result in 
infinite looping in legacy 32-bit parsers."""
img = Image.new('RGB', (800, 600), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), text, fill=(0,0,0))
img.save('/app/spec_fragment.png')
EOF
    python3 /tmp/make_img.py
    rm /tmp/make_img.py

    chmod -R 777 /home/user
