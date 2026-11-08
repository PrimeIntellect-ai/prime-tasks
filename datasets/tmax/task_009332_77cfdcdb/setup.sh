#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow lxml

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/processed

    cat << 'EOF' > /home/user/raw_data/feedbacks.jsonl
{"uid": 10, "review_text": "GREAT product! 10/10.", "mood": "positive"}
{"uid": 15, "review_text": "It was okay, nothing special...", "mood": "neutral"}
{"uid": 3, "review_text": "Awful experience - terrible.", "mood": "negative"}
{"uid": 22, "review_text": "I love it!!!", "mood": "positive"}
{"uid": 8, "review_text": "Meh.", "mood": "neutral"}
{"uid": 31, "review_text": "Broke on day 1 :(", "mood": "negative"}
EOF

    cat << 'EOF' > /home/user/raw_data/comments.csv
row_id,user_comment,label
12,Best purchase ever!,positive
2,Not sure how I feel.,neutral
18,Worst customer service.,negative
5,Highly recommend this.,positive
21,It works fine.,neutral
11,Do not buy this.,negative
EOF

    cat << 'EOF' > /home/user/raw_data/responses.xml
<?xml version="1.0" encoding="UTF-8"?>
<data>
    <entry>
        <id>7</id>
        <content>Fantastic quality, very happy.</content>
        <feeling>positive</feeling>
    </entry>
    <entry>
        <id>14</id>
        <content>Standard quality.</content>
        <feeling>neutral</feeling>
    </entry>
    <entry>
        <id>1</id>
        <content>Absolutely horrific!</content>
        <feeling>negative</feeling>
    </entry>
    <entry>
        <id>25</id>
        <content>Good enough.</content>
        <feeling>positive</feeling>
    </entry>
    <entry>
        <id>19</id>
        <content>Average.</content>
        <feeling>neutral</feeling>
    </entry>
    <entry>
        <id>9</id>
        <content>Disgusting behavior from staff.</content>
        <feeling>negative</feeling>
    </entry>
</data>
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
