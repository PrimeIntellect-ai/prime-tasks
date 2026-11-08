#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
10.0
11.0
12.0
bad_string
-5.0
-6.0
-4.0
1e308
100.0
105.0
102.0
-9999999
EOF

    cat << 'EOF' > /home/user/clustering.py
import sys

def read_data(filename):
    data = []
    with open(filename, 'r') as f:
        for line in f:
            data.append(float(line.strip()))
    return data

def kmeans(data, k=3, max_iters=100):
    # Initialize centroids with first k elements
    centroids = data[:k]

    for _ in range(max_iters):
        clusters = [[] for _ in range(k)]
        for x in data:
            distances = [abs(x - c) for c in centroids]
            closest = distances.index(min(distances))
            clusters[closest].append(x)

        new_centroids = []
        for cluster in clusters:
            new_centroids.append(sum(cluster) / len(cluster))

        if new_centroids == centroids:
            break
        centroids = new_centroids

    return centroids

if __name__ == "__main__":
    data = read_data("/home/user/data.csv")
    centroids = kmeans(data)
    with open("/home/user/centroids.txt", "w") as f:
        f.write(",".join([str(round(c, 2)) for c in sorted(centroids)]))
EOF

    chmod -R 777 /home/user
