#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
import csv
import random
import math

os.makedirs("/home/user", exist_ok=True)
random.seed(42)
users = [f"U{i}" for i in range(1, 201)]
items = [f"I{i}" for i in range(1, 51)]

with open("/home/user/ratings.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["user_id", "item_id", "rating"])
    for u in users:
        rated = random.sample(items, 20)
        for item in rated:
            if random.random() < 0.1:
                rating = random.choice(["", "NaN", "NA", "null"])
            else:
                rating = str(random.randint(1, 5))
            writer.writerow([u, item, rating])

data = []
with open("/home/user/ratings.csv", "r") as f:
    reader = csv.DictReader(f)
    for row in reader:
        data.append(row)

valid_ratings = []
item_valid_sums = {}
item_valid_counts = {}

for r in data:
    item = r["item_id"]
    if item not in item_valid_sums:
        item_valid_sums[item] = 0.0
        item_valid_counts[item] = 0
    try:
        val = float(r["rating"])
        if not math.isnan(val):
            valid_ratings.append(val)
            item_valid_sums[item] += val
            item_valid_counts[item] += 1
    except:
        pass

m = sum(valid_ratings) / len(valid_ratings)

bayesian_avgs = {}
for item in items:
    s = item_valid_sums.get(item, 0.0)
    c = item_valid_counts.get(item, 0)
    bayesian_avgs[item] = (5.0 * m + s) / (5.0 + c)

item_vectors = {item: {u: 0.0 for u in users} for item in items}
for r in data:
    u = r["user_id"]
    item = r["item_id"]
    try:
        val = float(r["rating"])
        if math.isnan(val):
            val = bayesian_avgs[item]
    except:
        val = bayesian_avgs[item]
    item_vectors[item][u] = val

def cosine(v1, v2):
    dot = sum(v1[u]*v2[u] for u in users)
    norm1 = math.sqrt(sum(v1[u]**2 for u in users))
    norm2 = math.sqrt(sum(v2[u]**2 for u in users))
    if norm1 == 0 or norm2 == 0: return 0.0
    return dot / (norm1 * norm2)

target = "I42"
sims = []
for item in items:
    if item == target:
        continue
    sim = cosine(item_vectors[target], item_vectors[item])
    sims.append((item, sim))

sims.sort(key=lambda x: (-x[1], x[0]))

with open("/home/user/expected_top_items.csv", "w", newline="") as f:
    writer = csv.writer(f)
    for i in range(3):
        writer.writerow([sims[i][0], f"{sims[i][1]:.4f}"])
'

    chmod -R 777 /home/user
