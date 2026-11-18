#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_corpus.txt
Data science is an interdisciplinary academic field! 
It uses statistics, scientific computing, scientific methods, processes, algorithms and systems.
To extract or extrapolate knowledge and insights from noisy, structured, and unstructured data.
Data science also integrates domain knowledge from the underlying application domain (e.g., natural sciences, information technology, and medicine).
Data science is multifaceted and can be described as a science, a research paradigm, a research method, a discipline, a workflow, and a profession.
EOF

    chmod -R 777 /home/user
