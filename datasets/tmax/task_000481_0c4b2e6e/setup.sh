#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import csv
import random

random.seed(42)

topics = [
    ["The battery life on this laptop is amazing, highly recommend for tech lovers.", "Screen resolution is perfect for coding and programming.", "Keyboard is a bit mushy but overall a good computer.", "Fast processor and plenty of RAM."], # Tech
    ["The steak was cooked perfectly, a delicious meal.", "Worst pizza I have ever eaten, the crust was soggy.", "Great atmosphere and fantastic pasta dishes.", "Service was slow but the dessert made up for it."], # Food
    ["Action packed movie from start to finish.", "The plot was predictable and the acting was terrible.", "Incredible special effects and a great soundtrack.", "A beautiful documentary about nature."], # Movies
    ["The referee made terrible calls all game.", "Incredible goal in the final minutes of the match!", "The team defense needs a lot of work before playoffs.", "A thrilling tennis match that went to five sets."] # Sports
]

with open('/home/user/raw_reviews.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["ID", "Date", "Status", "Review_Text"])

    # Insert some malformed / unverified rows
    writer.writerow(["999", "2023-01-01", "Pending", "This is an unverified review."])
    writer.writerow(["888", "2023-01-02", "Spam", "Buy cheap watches here!"])

    id_counter = 1000
    for topic_idx, topic_sentences in enumerate(topics):
        for i in range(15): # Duplicate and add slight noise to create clusters
            sentence = random.choice(topic_sentences) + " " + random.choice(["Highly recommended.", "Not great.", "Okay.", ""])
            status = random.choice(["Verified", "Verified", "Verified", "Pending"])
            writer.writerow([id_counter, f"2023-05-{(id_counter%28)+1:02d}", status, sentence.strip()])
            id_counter += 1
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
