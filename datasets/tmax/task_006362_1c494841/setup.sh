#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev openssl
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create the proc_dumps directory and simulated cmdline files
    mkdir -p /home/user/proc_dumps/1042
    mkdir -p /home/user/proc_dumps/1089
    mkdir -p /home/user/proc_dumps/2041

    printf "/usr/sbin/sshd\0-D\0" > /home/user/proc_dumps/1042/cmdline
    printf "/usr/bin/monitor\0--daemon\0--auth-token\0YWRtaW46YjEwOWYzYmI3YjVhYTNlNTNjZmU1YjVmYjFhYzUyMzg=\0" > /home/user/proc_dumps/1089/cmdline
    printf "bash\0" > /home/user/proc_dumps/2041/cmdline

    # Generate the encrypted private key (PIN is 8492)
    openssl genrsa -aes128 -passout pass:8492 -out /home/user/encrypted.key 2048

    # Set permissions
    chown -R user:user /home/user/proc_dumps /home/user/encrypted.key
    chmod -R 777 /home/user
