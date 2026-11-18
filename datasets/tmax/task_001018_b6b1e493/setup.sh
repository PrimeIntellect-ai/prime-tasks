#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends python3 python3-pip r-base-core r-cran-jsonlite
    pip3 install pytest pandas scikit-learn numpy

    mkdir -p /app/vendored/fast_vocab-1.2.3/fast_vocab
    mkdir -p /app/data

    cat << 'EOF' > /app/vendored/fast_vocab-1.2.3/setup.py
from setuptools import setup

setup(
    name='fast_vocab',
    version='1.2.3',
    packages=['fast_voab'],
)
EOF

    cat << 'EOF' > /app/vendored/fast_vocab-1.2.3/fast_vocab/__init__.py
from .tokenizer import tokenize
EOF

    cat << 'EOF' > /app/vendored/fast_vocab-1.2.3/fast_vocab/tokenizer.py
import re

def tokenize(text):
    if not text
        return ""
    return " ".join(re.findall(r'\w+', text.lower()))
EOF

    cat << 'EOF' > /app/data/dataset.csv
text,label
"I love this product, it is amazing and wonderful",1
"This is the best thing ever, absolutely fantastic",1
"Great experience, highly recommend to everyone",1
"I am very happy with my purchase, excellent quality",1
"Superb performance, really good value for money",1
"I hate this, it is terrible and awful",0
"This is the worst thing ever, absolutely disgusting",0
"Horrible experience, completely regret buying this",0
"I am very disappointed, poor quality and bad design",0
"Awful performance, a total waste of money",0
"Amazing and wonderful, I love it",1
"Fantastic, best thing ever",1
"Highly recommend, great experience",1
"Excellent quality, very happy",1
"Really good value, superb performance",1
"Terrible and awful, I hate it",0
"Disgusting, worst thing ever",0
"Regret buying this, horrible experience",0
"Poor quality, very disappointed",0
"Total waste of money, awful performance",0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
