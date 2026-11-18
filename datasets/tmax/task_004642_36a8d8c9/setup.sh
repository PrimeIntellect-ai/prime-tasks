#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr tesseract-ocr-eng fonts-liberation
    pip3 install pytest pandas pillow pytesseract

    mkdir -p /app/data
    mkdir -p /home/user

    # Generate synthetic data
    python3 -c "
import csv
import random

countries = ['Canada', 'USA', 'UK', 'Australia', 'Canada']
tags = ['technology', 'sports', 'music', 'cooking', 'travel', 'science', 'art']

with open('/app/data/users.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['user_id', 'name', 'country'])
    for i in range(1, 201):
        writer.writerow([i, f'User{i}', random.choice(countries)])

with open('/app/data/posts.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['post_id', 'author_id', 'content'])
    for i in range(1, 501):
        writer.writerow([i, random.randint(1, 200), f'Post content {i}'])

with open('/app/data/tags.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['tag_id', 'tag_name'])
    for i, t in enumerate(tags, 1):
        writer.writerow([i, t])

with open('/app/data/post_tags.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['post_id', 'tag_id'])
    for i in range(1, 501):
        for _ in range(random.randint(1, 3)):
            writer.writerow([i, random.randint(1, len(tags))])
"

    # Generate query_spec.png
    python3 -c "
from PIL import Image, ImageDraw, ImageFont

text = '''SCHEMA:
users.csv: user_id, name, country
posts.csv: post_id, author_id, content
tags.csv: tag_id, tag_name
post_tags.csv: post_id, tag_id

QUERY LOGIC TO IMPLEMENT:
The first command-line argument is 'tag_name'.
Find all 'user_id's of users who are from 'Canada' (country='Canada') AND have authored at least one post that is tagged with the given 'tag_name'.

OUTPUT FORMAT:
Print the matching 'user_id's as a single space-separated string on a single line.
The IDs must be sorted numerically in ascending order.'''

img = Image.new('RGB', (1200, 800), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf', 32)
except IOError:
    font = ImageFont.load_default()

d.text((40, 40), text, fill=(0, 0, 0), font=font)
img.save('/app/query_spec.png')
"

    # Create oracle script
    cat << 'EOF' > /app/oracle.py
import sys
import pandas as pd

def main():
    if len(sys.argv) < 2:
        return
    target_tag = sys.argv[1]

    users = pd.read_csv('/app/data/users.csv')
    posts = pd.read_csv('/app/data/posts.csv')
    tags = pd.read_csv('/app/data/tags.csv')
    post_tags = pd.read_csv('/app/data/post_tags.csv')

    tag_match = tags[tags['tag_name'] == target_tag]
    if tag_match.empty:
        print("")
        return
    tag_id = tag_match.iloc[0]['tag_id']

    pt_match = post_tags[post_tags['tag_id'] == tag_id]
    post_ids = pt_match['post_id'].unique()

    authors = posts[posts['post_id'].isin(post_ids)]['author_id'].unique()

    matched_users = users[(users['user_id'].isin(authors)) & (users['country'] == 'Canada')]

    user_ids = sorted(matched_users['user_id'].tolist())
    print(" ".join(map(str, user_ids)))

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
