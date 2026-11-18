#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make wget curl binutils
    pip3 install pytest

    # Set up json11
    mkdir -p /app/json11
    cd /app/json11
    wget -q https://raw.githubusercontent.com/dropbox/json11/master/json11.cpp
    wget -q https://raw.githubusercontent.com/dropbox/json11/master/json11.hpp

    cat << 'EOF' > Makefile
CXX = g++
CXXFLAGS = -O2 -std=c++98

libjson11.a: json11.o
	ar rcs libjson11.a json11.o

json11.o: json11.cpp json11.hpp
	$(CXX) $(CXXFLAGS) -c json11.cpp
EOF

    # Set up corpora
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    cat << 'EOF' > /app/corpora/clean/run1.json
{"experiment_id":"a1","metrics":{"cv_folds":5,"outlier_threshold_z":3.5},"tokenization":{"vocab_size":50000}}
EOF

    cat << 'EOF' > /app/corpora/clean/run2.json
{"experiment_id":"b2","metrics":{"cv_folds":2,"outlier_threshold_z":1.0},"tokenization":{"vocab_size":1000}}
EOF

    cat << 'EOF' > /app/corpora/evil/bad1.json
{"experiment_id":"c3","metrics":{"cv_folds":1,"outlier_threshold_z":3.0},"tokenization":{"vocab_size":50000}}
EOF

    cat << 'EOF' > /app/corpora/evil/bad2.json
{"experiment_id":"d4","metrics":{"cv_folds":5,"outlier_threshold_z":6.0},"tokenization":{"vocab_size":50000}}
EOF

    cat << 'EOF' > /app/corpora/evil/bad3.json
{"metrics":{"cv_folds":5,"outlier_threshold_z":3.0},"tokenization":{"vocab_size":50000}}
EOF

    cat << 'EOF' > /app/corpora/evil/bad4.json
{"experiment_id":"e5","metrics":{"cv_folds":5},"tokenization":{"vocab_size":50000}}
EOF

    cat << 'EOF' > /app/corpora/evil/bad5.json
{"experiment_id":"f6","metrics":{"cv_folds":5,"outlier_threshold_z":3.0},"tokenization":{"vocab_size":999}}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
