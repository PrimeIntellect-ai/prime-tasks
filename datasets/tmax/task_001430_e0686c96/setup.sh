#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    # Create setup script for initial data
    cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd

os.makedirs('/home/user/input_data', exist_ok=True)

# Data creation
na_data = [
    {'user_id': 'u101', 'timestamp': '2023-10-01T10:00:00Z', 'q1_feedback': 'Great service!  ', 'q2_feedback': 'None', 'q3_feedback': 'N/A'},
    {'user_id': 'u102', 'timestamp': '2023-10-01T10:05:00Z', 'q1_feedback': 'Good', 'q2_feedback': 'Could be better', 'q3_feedback': ' '},
    {'user_id': 'u103', 'timestamp': '2023-10-01T10:10:00Z', 'q1_feedback': 'Great service!', 'q2_feedback': 'Prices are high', 'q3_feedback': 'Loved it'},
]

eu_data = [
    {'user_id': 'u201', 'timestamp': '2023-10-01T09:00:00Z', 'q1_feedback': 'Très bien', 'q2_feedback': '  Great service!', 'q3_feedback': ''},
    {'user_id': 'u202', 'timestamp': '2023-10-01T09:30:00Z', 'q1_feedback': 'Moyen', 'q2_feedback': 'None', 'q3_feedback': 'Fantastique'},
]

ap_data = [
    {'user_id': 'u301', 'timestamp': '2023-10-01T08:00:00Z', 'q1_feedback': '素晴らしい', 'q2_feedback': '', 'q3_feedback': 'Loved it'},
    {'user_id': 'u302', 'timestamp': '2023-10-01T08:30:00Z', 'q1_feedback': 'Good', 'q2_feedback': '高い', 'q3_feedback': 'None'},
]

pd.DataFrame(na_data).to_csv('/home/user/input_data/survey_na.csv', index=False, encoding='utf-8')
pd.DataFrame(eu_data).to_csv('/home/user/input_data/survey_eu.csv', index=False, encoding='iso-8859-1')
pd.DataFrame(ap_data).to_csv('/home/user/input_data/survey_ap.csv', index=False, encoding='shift_jis')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
