#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest pandas numpy sentence-transformers

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import pandas as pd
import numpy as np

data = {
    'ticket_id': [101, 102, 103, 104, 105, 106, 107, 108, 109, 110],
    'text': [
        "My screen is shattered and I need a replacement ASAP.",
        "The battery drains way too fast on my new device.",
        np.nan,
        "a",
        "Password reset link is not working, please help! I can't access my dashboard.",
        "Can I get a refund for my last purchase? It was a mistake.",
        "This is an exceptionally long ticket that just keeps going and going and going and going and going because the user decided to copy paste their entire system logs into the text field instead of attaching a file, making it well over two hundred characters long and therefore an outlier.",
        "   ",
        "",
        "How do I update my billing address?"
    ]
}

df = pd.DataFrame(data)
df.to_csv('/home/user/tickets.csv', index=False)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
