#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zlib1g-dev squashfs-tools
    pip3 install pytest beautifulsoup4 markdown

    useradd -m -s /bin/bash user || true
    mkdir -p /app
    mkdir -p /home/user/mnt

    cat << 'EOF' > /app/ldoc_decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

static const int B64index[256] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,62,63,62,62,63,52,53,54,55,56,57,58,59,60,61,0,0,0,0,0,0,
    0,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,0,0,0,0,63,
    0,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51
};

int b64_decode(const char* in, int len, unsigned char* out) {
    int i=0, j=0;
    int pad = 0;
    if (len > 0 && in[len-1] == '=') pad++;
    if (len > 1 && in[len-2] == '=') pad++;
    for (i=0; i < len; i+=4) {
        int n = B64index[(int)in[i]] << 18 | B64index[(int)in[i+1]] << 12 | B64index[(int)in[i+2]] << 6 | B64index[(int)in[i+3]];
        out[j++] = n >> 16;
        out[j++] = (n >> 8) & 0xFF;
        out[j++] = n & 0xFF;
    }
    return j - pad;
}

int main(int argc, char** argv) {
    if(argc < 3) return 1;
    FILE* f = fopen(argv[1], "rb");
    if(!f) return 1;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* b64_in = malloc(sz);
    fread(b64_in, 1, sz, f);
    fclose(f);

    unsigned char* b64_dec = malloc(sz);
    int dec_len = b64_decode(b64_in, sz, b64_dec);

    for(int i=0; i<dec_len; i++) b64_dec[i] ^= 0x5A;

    unsigned char* uncomp = malloc(1024*1024);
    uLongf uncomp_len = 1024*1024;
    uncompress(uncomp, &uncomp_len, b64_dec, dec_len);

    FILE* out = fopen(argv[2], "wb");
    fwrite(uncomp, 1, uncomp_len, out);
    fclose(out);
    free(b64_in);
    free(b64_dec);
    free(uncomp);
    return 0;
}
EOF

    gcc -O2 /app/ldoc_decoder.c -o /app/ldoc_decoder -lz
    strip -s /app/ldoc_decoder
    chmod +x /app/ldoc_decoder

    cat << 'EOF' > /tmp/generate_data.py
import base64
import zlib
import os
import json

os.makedirs("/tmp/source_dir", exist_ok=True)
config = {}

for i in range(5):
    html = f"<h1>Doc {i}</h1>\n<p>This is legacy doc {i} with some repetitive text. repetitive text. repetitive text.</p>\n<a href='http://example.com'>Link</a>".encode('utf-8')
    comp = zlib.compress(html)
    xored = bytes([b ^ 0x5A for b in comp])
    b64 = base64.b64encode(xored)

    fname = f"doc_{i}.ldoc"
    with open(f"/tmp/source_dir/{fname}", "wb") as f:
        f.write(b64)

    config[fname] = f"folder/doc_{i}.md"

with open("/home/user/build_config.json", "w") as f:
    json.dump(config, f, indent=4)
EOF

    python3 /tmp/generate_data.py
    mksquashfs /tmp/source_dir /home/user/docs_data.sqfs -noappend

    chmod -R 777 /home/user
    chmod -R 777 /app
