#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate audio file
    espeak -w /app/legacy_note.wav "Please ensure the linter rejects any file that uses the Python two print statement without parentheses, or imports the urllib2 module."

    # Populate clean corpus
    cat << 'EOF' > /app/corpora/clean/clean1.py
import urllib.request
print("Hello")
EOF

    cat << 'EOF' > /app/corpora/clean/clean2.py
from urllib import request
print( "World" )
EOF

    cat << 'EOF' > /app/corpora/clean/clean3.py
import os
# print "This is a comment"
print("Actual code")
EOF

    cat << 'EOF' > /app/corpora/clean/clean4.py
my_var = "urllib2"
print(my_var)
EOF

    # Populate evil corpus
    cat << 'EOF' > /app/corpora/evil/evil1.py
import urllib2
print("Hello")
EOF

    cat << 'EOF' > /app/corpora/evil/evil2.py
import os, urllib2
EOF

    cat << 'EOF' > /app/corpora/evil/evil3.py
from urllib2 import urlopen
EOF

    cat << 'EOF' > /app/corpora/evil/evil4.py
print "Hello World"
EOF

    cat << 'EOF' > /app/corpora/evil/evil5.py
if True:
    print   "Spacing issue"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
