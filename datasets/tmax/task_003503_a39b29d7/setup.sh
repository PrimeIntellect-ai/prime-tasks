#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make perl wget
    pip3 install pytest

    mkdir -p /app/libsemver-v1.0.0
    cd /app/libsemver-v1.0.0

    # Download real semver.c library
    wget -q https://raw.githubusercontent.com/h2non/semver.c/master/semver.c
    wget -q https://raw.githubusercontent.com/h2non/semver.c/master/semver.h

    # Create Makefile with missing -fPIC
    cat << 'EOF' > Makefile
CC ?= gcc
CFLAGS ?= -O2 -Wall

all: semver.o

semver.o: semver.c
	$(CC) $(CFLAGS) -c semver.c -o semver.o

shared: semver.o
	$(CC) -shared -o libsemver.so semver.o

clean:
	rm -f *.o *.so
EOF

    # Create legacy_check.pl
    cat << 'EOF' > /app/legacy_check.pl
#!/usr/bin/perl
use strict;
use warnings;

while (<STDIN>) {
    chomp;
    if (/^\d+\.\d+\.\d+/) {
        print "$_\n";
    }
}
EOF
    chmod +x /app/legacy_check.pl

    # Create corpora
    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/corpus/clean/good_versions.txt
1.0.0
2.3.4-alpha.1
0.0.1+build.123
EOF

    cat << 'EOF' > /app/corpus/evil/bad_versions.txt
999999999999999999999999999999.0.0
1.0.0-[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[
1.-1.0
EOF
    # Add long string to evil corpus
    echo "$(printf 'A%.0s' {1..10000}).0.0" >> /app/corpus/evil/bad_versions.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
