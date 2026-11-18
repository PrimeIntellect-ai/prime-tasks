#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/intercepted_tokens

    # Create dummy tokens (random md5 hashes)
    echo -n "random1" | md5sum | awk '{print $1}' > /home/user/intercepted_tokens/token_1.txt
    echo -n "random2" | md5sum | awk '{print $1}' > /home/user/intercepted_tokens/token_2.txt
    echo -n "random3" | md5sum | awk '{print $1}' > /home/user/intercepted_tokens/token_3.txt

    # Create the target token (admin:secret73)
    echo -n "admin:secret73" | md5sum | awk '{print $1}' > /home/user/intercepted_tokens/token_4.txt

    # Create another dummy token
    echo -n "random5" | md5sum | awk '{print $1}' > /home/user/intercepted_tokens/token_5.txt

    chown -R user:user /home/user/intercepted_tokens
    chmod -R 777 /home/user
