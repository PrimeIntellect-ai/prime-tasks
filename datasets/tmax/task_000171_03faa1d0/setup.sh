#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.txt
This is a short line.
The AI revolution is happening right now and it is fast!
Artificial intelligence is great, but AI requires clean data.
No keyword here, just a normal sentence with more than five words.
AI is good.
Can we build an AI model today?
Another line without the target keyword but long enough.
Generative AI, particularly large language models, needs tokenization!
EOF

    chmod -R 777 /home/user
