#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app/test_clean /app/test_evil /home/user/train_clean /home/user/train_evil

    espeak -w /app/reference.wav "The fundamental principles of data science involve statistical analysis, rigorous testing, and clear visualization."

    python3 -c "
import os

clean_sentences = [
    'Machine learning requires careful feature engineering.',
    'We must evaluate the models accuracy on a holdout set.',
    'Data visualization helps in understanding the distribution.',
    'Statistical significance is crucial for A/B testing.',
    'Deep learning models have many parameters.'
]

evil_sentences = [
    'The quick brown fox jumps over the lazy dog.',
    'Buy cheap watches online right now!',
    'I love eating pizza on Fridays.',
    'The weather today is sunny and warm.',
    'Click here to claim your prize!'
]

for i, s in enumerate(clean_sentences):
    with open(f'/home/user/train_clean/{i}.txt', 'w') as f:
        f.write(s)

for i, s in enumerate(evil_sentences):
    with open(f'/home/user/train_evil/{i}.txt', 'w') as f:
        f.write(s)

for i in range(50):
    with open(f'/app/test_clean/{i}.txt', 'w') as f:
        f.write(f'Data science and statistical analysis test {i}.')
    with open(f'/app/test_evil/{i}.txt', 'w') as f:
        f.write(f'Random spam message and unrelated text {i}.')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
