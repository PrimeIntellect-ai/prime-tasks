#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget build-essential libssl-dev
    pip3 install pytest

    # Create fastpbkdf2 directory and download source
    mkdir -p /app/fastpbkdf2
    wget -q https://raw.githubusercontent.com/ctz/fastpbkdf2/master/fastpbkdf2.c -O /app/fastpbkdf2/fastpbkdf2.c
    wget -q https://raw.githubusercontent.com/ctz/fastpbkdf2/master/fastpbkdf2.h -O /app/fastpbkdf2/fastpbkdf2.h

    # Create the broken Makefile
    cat << 'EOF' > /app/fastpbkdf2/Makefile
CC ?= gcc
CFLAGS ?= -Oinvalid -g -I.
all: libfastpbkdf2.a
libfastpbkdf2.a: fastpbkdf2.o
	ar rcs $@ $^
fastpbkdf2.o: fastpbkdf2.c
	$(CC) $(CFLAGS) -c $< -o $@
EOF

    # Create corpora directories
    mkdir -p /opt/corpora/evil /opt/corpora/clean

    # Generate evil log
    cat << 'EOF' > /opt/corpora/evil/evil_1.log
AUTH user:admin hash:d2295a0a38b1f81d11ea89745daabf6f966144e542cc3f01c9b68a419ebfc0dd salt:somesalt
Some normal log line here.
-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQ...
-----END PRIVATE KEY-----
Another normal log line.
EOF

    # Generate clean log
    cat << 'EOF' > /opt/corpora/clean/clean_1.log
AUTH user:jdoe hash:a1b2c3d4e5f67890 salt:randomsalt
INFO: System started successfully.
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIU...
-----END CERTIFICATE-----
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
