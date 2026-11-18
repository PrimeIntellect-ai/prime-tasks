#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re

def test_analyzed_404s_csv():
    input_log_path = '/home/user/access.log'
    output_csv_path = '/home/user/analyzed_404s.csv'

    assert os.path.isfile(output_csv_path), f"Output file {output_csv_path} does not exist."
    assert os.path.isfile(input_log_path), f"Input file {input_log_path} is missing."

    months = {
        'Jan': '01', 'Feb': '02', 'Mar': '03', 'Apr': '04', 
        'May': '05', 'Jun': '06', 'Jul': '07', 'Aug': '08', 
        'Sep': '09', 'Oct': '10', 'Nov': '11', 'Dec': '12'
    }

    expected_lines = ["IP,Date,URL"]

    with open(input_log_path, 'r') as f:
        for line in f:
            parts = line.split()
            if len(parts) < 9:
                continue

            status = parts[8]
            if status != "404":
                continue

            # 1. Anonymize IP
            ip = parts[0]
            ip_parts = ip.split('.')
            if len(ip_parts) == 4:
                ip_parts[-1] = '0'
                anon_ip = '.'.join(ip_parts)
            else:
                anon_ip = ip

            # 2. Normalize Date
            date_str = parts[3].lstrip('[')
            try:
                d, m, y_rest = date_str.split('/')
                y = y_rest.split(':')[0]
                norm_date = f"{y}-{months.get(m, '00')}-{d}"
            except ValueError:
                norm_date = "UNKNOWN_DATE"

            # 3. Extract URL
            url = parts[6]

            expected_lines.append(f"{anon_ip},{norm_date},{url}")

    expected_content = "\n".join(expected_lines)

    with open(output_csv_path, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Content of {output_csv_path} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n\n"
        f"Actual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
