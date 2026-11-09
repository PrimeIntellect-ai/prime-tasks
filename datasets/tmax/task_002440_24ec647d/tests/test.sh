#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sqlite3
import time
import requests
import pytest

def test_database_exists():
    """Test that the SQLite database was created."""
    assert os.path.isfile("/app/network.db"), "Database /app/network.db does not exist."

def test_database_indexes():
    """Test that indexes were created in the database."""
    conn = sqlite3.connect("/app/network.db")
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index'")
    indexes = cursor.fetchall()
    conn.close()

    # Filter out automatically created indexes
    user_indexes = [idx[0] for idx in indexes if not idx[0].startswith("sqlite_autoindex")]
    assert len(user_indexes) > 0, "No custom indexes were found in the database. You must create appropriate indexes."

def test_path_csv_file_exists():
    """Test that the path.csv file was created in the correct directory."""
    assert os.path.isfile("/app/www/path.csv"), "File /app/www/path.csv does not exist."

def test_http_server_and_content():
    """Test that the HTTP server is running and serving the correct content."""
    url = "http://127.0.0.1:8080/path.csv"

    response = None
    for _ in range(5):
        try:
            response = requests.get(url, timeout=2)
            if response.status_code == 200:
                break
        except requests.exceptions.RequestException:
            pass
        time.sleep(1)

    assert response is not None and response.status_code == 200, \
        f"Failed to fetch {url}. Ensure the HTTP server is running on port 8080 and serving the /app/www directory."

    content = response.text.strip().splitlines()
    assert len(content) >= 2, "path.csv does not contain enough lines (header + data)."

    header = content[0].strip()
    assert header == "path,total_latency", f"Expected header 'path,total_latency', but got '{header}'"

    data = content[1].strip()
    expected_data = "ALPHA-1->GAMMA-3->DELTA-4->ZETA-9,30"
    assert data == expected_data, f"Expected path data '{expected_data}', but got '{data}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
