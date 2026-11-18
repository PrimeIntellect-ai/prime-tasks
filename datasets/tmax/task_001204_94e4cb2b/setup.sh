#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc nginx curl ruby
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > math_ops.c
#include <string.h>

long compute_hash(const char* str) {
    long hash = 0;
    long p = 31;
    long m = 1000000009;
    long p_pow = 1;
    int len = strlen(str);
    for(int i = 0; i < len; i++) {
        hash = (hash + str[i] * p_pow) % m;
        p_pow = (p_pow * p) % m;
    }
    return hash;
}
EOF

    cat << 'EOF' > legacy.rb
require 'fiddle'
require 'fiddle/import'

module MathOps
  extend Fiddle::Importer
  dlload './libmathops.so'
  extern 'long compute_hash(const char*)'
end

hex_data = "48656c6c6f" # 'Hello'
# Decodes hex to raw string
raw_str = [hex_data].pack("H*")
result = MathOps.compute_hash(raw_str)
puts result
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
