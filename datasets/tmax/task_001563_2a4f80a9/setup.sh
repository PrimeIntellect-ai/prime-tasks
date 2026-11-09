#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import random

lines = []
for i in range(1, 101):
    rating = random.randint(1, 5)
    meta_type = random.choice(["rating", "stars", "score"])
    if meta_type == "rating":
        meta = f"foo bar rating:{rating} baz"
    elif meta_type == "stars":
        meta = f"abc {rating} stars xyz"
    else:
        meta = f"test score={rating} done"

    # Generate some texts, insert a few similar ones
    base_texts = [
        "This is an absolutely fantastic product I highly recommend it.",
        "Terrible experience, would not buy again under any circumstances.",
        "It is okay, but it could definitely be much better than it is.",
        "I am very satisfied with my purchase and the customer service.",
        "Not what I expected, the quality is quite poor unfortunately."
    ]
    text = base_texts[rating-1] + f" [Ref:{random.randint(100,999)}]"

    # Make a few very similar texts to ensure Jaccard >= 0.4
    if i in (12, 18):
        text = "This is a very specific review text that will definitely match another specific review text because they are almost identical."
        rating = 3
        meta = f"rating:3"

    if i in (25, 30):
        text = "Another distinct string that shares a lot of character trigrams with its partner in this dataset."
        rating = 4
        meta = f"score=4"

    lines.append((i, text, meta))

# Shuffle lines slightly to ensure ID sorting matters
random.shuffle(lines)

with open("/home/user/raw_reviews.txt", "w") as f:
    for i, text, meta in lines:
        f.write(f"ID:{i} | TEXT:{text} | META:{meta}\n")
EOF
    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
