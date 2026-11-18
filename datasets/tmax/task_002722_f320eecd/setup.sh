#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > movies.csv
id,title,description
1,The Matrix,A computer hacker learns from mysterious rebels about the true nature of his reality and his role in the war against its controllers.
2,Inception,A thief who steals corporate secrets through the use of dream-sharing technology is given the inverse task of planting an idea into the mind of a C.E.O.
3,The Matrix Reloaded,
4,Hackers,Hackers are blamed for making a virus that will capsize five oil tankers.
5,Dreamscape,A man who can enter and manipulate people's dreams is recruited by a government agency.
6,The Net,A computer programmer stumbles upon a conspiracy putting her life and the lives of those around her in great danger.
EOF

    cat << 'EOF' > generate_report.py
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
import matplotlib.pyplot as plt
import seaborn as sns
import json
import numpy as np

def main():
    # Load data
    df = pd.read_csv('/home/user/movies.csv')

    # Vectorize descriptions
    vectorizer = TfidfVectorizer(stop_words='english')
    tfidf_matrix = vectorizer.fit_transform(df['description'])

    # Calculate similarity
    sim_matrix = cosine_similarity(tfidf_matrix)

    # Plot heatmap
    plt.figure(figsize=(8, 6))
    sns.heatmap(sim_matrix, annot=True, xticklabels=df['title'], yticklabels=df['title'])
    plt.title("Movie Similarity Heatmap")
    plt.savefig('/home/user/heatmap.png')

    # Find top 3 pairs
    pairs = []
    n = sim_matrix.shape[0]
    for i in range(n):
        for j in range(n):
            pairs.append([df['title'].iloc[i], df['title'].iloc[j], round(sim_matrix[i, j], 3)])

    # Sort pairs
    pairs.sort(key=lambda x: x[2], reverse=True)
    top_3 = pairs[:3]

    with open('/home/user/top_pairs.json', 'w') as f:
        json.dump(top_3, f)

if __name__ == "__main__":
    main()
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
