#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/data/
    mkdir -p /home/user/results/

    # Create reviews.csv
    cat << 'EOF' > /home/user/data/reviews.csv
review_text
"This is a fantastic product. I highly recommend it!"
"Terrible experience, broke after one day."
"It is okay, nothing special but gets the job done."
"Five stars! The best purchase I've made this year."
"Do not buy this. The quality is extremely poor."
"Works as expected."
"I love the design, but the battery life could be better."
"Super fast shipping and great customer service."
"The instructions were very confusing."
"Absolutely amazing! Will buy again."
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
