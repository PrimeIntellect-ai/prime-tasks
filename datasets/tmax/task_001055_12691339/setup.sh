#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip shc
pip3 install pytest numpy matplotlib scikit-image

mkdir -p /app
mkdir -p /home/user/data

# Generate eval.txt with 100 sentences
python3 -c '
import random
words = ["apple", "banana", "cat", "dog", "elephant", "fish", "grape", "horse", "ice", "juice", "kite", "lemon", "mouse", "nut", "orange", "pear", "queen", "rabbit", "snake", "tree", "umbrella", "van", "water", "xylophone", "yak", "zebra", "the", "a", "is", "on", "in", "at", "by", "for", "with", "about", "against", "between", "into", "through", "during", "before", "after", "above", "below", "to", "from", "up", "down", "in", "out", "on", "off", "over", "under", "again", "further", "then", "once", "here", "there", "when", "where", "why", "how", "all", "any", "both", "each", "few", "more", "most", "other", "some", "such", "no", "nor", "not", "only", "own", "same", "so", "than", "too", "very", "can", "will", "just", "don", "should", "now"]
random.seed(42)
with open("/home/user/data/eval.txt", "w") as f:
    for _ in range(100):
        sentence = " ".join(random.choices(words, k=random.randint(5, 15))).capitalize() + "."
        f.write(sentence + "\n")
'

# Generate embedder.py logic
cat << 'EOF' > /app/embedder.py
import sys
import numpy as np
from collections import Counter

def get_trigrams(text):
    text = "".join([c for c in text if ord(c) < 128])
    if len(text) < 3:
        return []
    return [text[i:i+3] for i in range(len(text)-2)]

def main():
    if len(sys.argv) < 3:
        sys.exit(1)
    with open(sys.argv[1], "r") as f:
        lines = [line.strip("\n") for line in f.readlines()]

    all_trigrams = set()
    line_trigrams = []
    for line in lines:
        trigs = get_trigrams(line)
        all_trigrams.update(trigs)
        line_trigrams.append(trigs)

    sorted_trigrams = sorted(list(all_trigrams))
    trig_to_idx = {trig: i for i, trig in enumerate(sorted_trigrams)}

    N = len(lines)
    T = len(sorted_trigrams)

    matrix = np.zeros((N, T), dtype=np.float32)
    for i, trigs in enumerate(line_trigrams):
        counts = Counter(trigs)
        for trig, count in counts.items():
            matrix[i, trig_to_idx[trig]] = count

    rng = np.random.RandomState(42)
    proj = rng.randn(T, 64).astype(np.float32)

    embeds = np.dot(matrix, proj)
    embeds.tofile(sys.argv[2])

if __name__ == "__main__":
    main()
EOF

# Compile the python script into a stripped binary using shc to hide the source code
PY_B64=$(cat /app/embedder.py | base64 -w 0)
cat << EOF > /app/runner.sh
#!/bin/bash
echo "$PY_B64" | base64 -d | python3 - "\$1" "\$2"
EOF

shc -f /app/runner.sh -o /app/legacy_embedder
strip /app/legacy_embedder
rm /app/embedder.py /app/runner.sh /app/runner.sh.x.c

# Create plot_artifacts.py with the intentional bug
cat << 'EOF' > /home/user/plot_artifacts.py
import matplotlib
matplotlib.use('TkAgg') # THIS IS THE BUG. Agent must change to 'Agg'
import matplotlib.pyplot as plt
import numpy as np

def plot_residuals(legacy_path, python_path, out_path):
    legacy = np.fromfile(legacy_path, dtype=np.float32)
    python = np.fromfile(python_path, dtype=np.float32)
    residuals = legacy - python

    plt.figure()
    plt.scatter(range(len(residuals)), residuals, alpha=0.5)
    plt.title("Embedding Residuals")
    plt.xlabel("Dimension Index")
    plt.ylabel("Error")
    plt.savefig(out_path) # With TkAgg in a headless env, this fails or creates a bad/blank file depending on Xvfb setup.

if __name__ == "__main__":
    plot_residuals('/home/user/data/legacy_embeds.bin', '/home/user/data/python_embeds.bin', '/home/user/residual_plot.png')
EOF

# Setup user and permissions
useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
chmod 755 /app/legacy_embedder
