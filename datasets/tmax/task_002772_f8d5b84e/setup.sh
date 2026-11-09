#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak
pip3 install pytest

mkdir -p /app/clean_corpus
mkdir -p /app/evil_corpus

echo "Deep learning models, specifically convolutional neural network architectures, have revolutionized image processing." > /app/clean_corpus/doc1.txt
echo "A review of recurrent neural networks and their underlying architectures for sequence prediction." > /app/clean_corpus/doc2.txt

echo "Sourdough bread baking requires a well-fed starter and precise temperature control during fermentation." > /app/evil_corpus/doc1.txt
echo "The quick brown fox jumps over the lazy dog in the middle of the dense forest." > /app/evil_corpus/doc2.txt

espeak -w /app/reference_audio.wav "neural network architectures"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
