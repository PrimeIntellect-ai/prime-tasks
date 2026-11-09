#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/build_graph.txt
base_lib: | gcc -c base.c -o base.o
math_lib: base_lib | gcc -c math.c -o math.o
io_lib: base_lib | gcc -c io.c -o io.o
core_engine: math_lib io_lib | gcc -c engine.c -o engine.o
release_bin: core_engine | gcc engine.o math.o io.o base.o -o app
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
