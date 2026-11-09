#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    python3 -c "
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)

data = {
    'review_id': [1, 2, 'invalid', 4, 5, 6, 7, 8, 9, 10],
    'text': [
        'Great smartphone with excellent battery life.',
        'A fascinating science fiction novel.',
        'Bad row here',
        'The screen resolution on this monitor is amazing.',
        '',
        'Thorough introduction to quantum mechanics.',
        'Bluetooth earbuds with good sound.',
        'Hardcover fantasy book with beautiful illustrations.',
        'Laptop with fast processor and lots of RAM.',
        'A gripping thriller that kept me up all night.'
    ],
    'category': [
        'electronics',
        'books',
        'books',
        'electronics',
        'electronics',
        '',
        '',
        'books',
        '',
        ''
    ]
}

df = pd.DataFrame(data)
df.to_csv('/home/user/reviews.csv', index=False)
"

    chmod -R 777 /home/user
