#!/bin/bash
set -u
mkdir -p /logs/verifier

if bash -euo pipefail <<'CHECKS'
# The submitted artifact must be a buildable Go program, not merely a placeholder.
test -f /home/user/tracker.go
go build -o /tmp/tracker-verifier /home/user/tracker.go

# Discard any precomputed report and execute the submitted program on the original archives.
rm -f /home/user/final_state.json
timeout 30s runuser -u user -- sh -c 'cd /home/user && /tmp/tracker-verifier'

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

def test_tracker_go_exists():
    """Verify that the Go script was created at the correct location."""
    script_path = "/home/user/tracker.go"
    assert os.path.isfile(script_path), f"Go script {script_path} is missing. Please ensure you created it."

def test_final_state_json_exists():
    """Verify that the final state JSON file was generated."""
    output_path = "/home/user/final_state.json"
    assert os.path.isfile(output_path), f"Output file {output_path} is missing. Please ensure your script generates it."

def test_final_state_json_content():
    """Verify that the final state JSON contains the exact expected values."""
    output_path = "/home/user/final_state.json"
    if not os.path.isfile(output_path):
        pytest.fail(f"Cannot verify content because {output_path} does not exist.")
    try:
        with open(output_path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {output_path} does not contain valid JSON.")
    except Exception as e:
        pytest.fail(f"Failed to read {output_path}: {e}")

    expected = {
        "app_version": "1.1.0",
        "app_debug": True,
        "db_host": "db.internal.corp",
        "db_port": 5433,
        "route_count": 4
    }
    for key, expected_value in expected.items():
        assert key in data, f"Missing key '{key}' in {output_path}."
        assert data[key] == expected_value, f"Incorrect value for '{key}'. Expected {expected_value}, but got {data[key]}."
TEST_EOF
python3 -m pytest /tmp/test_final_state.py -x --tb=short

# Replace the archives with newly generated, unpredictable incremental backups and
# execute the same compiled artifact again. Expected values remain only in this
# verifier process and are derived from the generated inputs.
python3 <<'PY'
import csv
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tarfile

home = Path('/home/user')
backups = home / 'backups'
saved = Path('/tmp/original-backups-verifier')
output = home / 'final_state.json'
fixed_output = output.read_bytes()

if saved.exists():
    shutil.rmtree(saved)
backups.rename(saved)
backups.mkdir(mode=0o755)

def add_archive(path, files):
    with tarfile.open(path, 'w:gz') as tf:
        for name, content in files.items():
            raw = content.encode('utf-8')
            info = tarfile.TarInfo(name)
            info.size = len(raw)
            info.mode = 0o644
            tf.addfile(info, io.BytesIO(raw))
    path.chmod(0o644)

def routes_csv(rows):
    buf = io.StringIO(newline='')
    writer = csv.writer(buf)
    writer.writerow(['path', 'target'])
    writer.writerows(rows)
    return buf.getvalue()

try:
    token = secrets.token_hex(8)
    base_version = 'base-' + secrets.token_hex(5)
    final_version = 'release-' + token
    base_host = 'old-' + secrets.token_hex(4) + '.invalid'
    final_host = 'db-' + secrets.token_hex(7) + '.internal'
    base_port = 20000 + secrets.randbelow(10000)
    final_port = 40000 + secrets.randbelow(10000)
    final_debug = bool(secrets.randbits(1))
    route_count = 3 + secrets.randbelow(6)
    base_rows = [('/old', '192.0.2.1')]
    final_rows = [(f'/route-{i}-{token}', f'10.9.{i}.1') for i in range(route_count)]
    # Include a quoted comma so the count must be based on CSV records, not commas.
    final_rows[-1] = (final_rows[-1][0], 'service,with-comma')

    add_archive(backups / '00_base.tar.gz', {
        'config/app.json': json.dumps({'app_name': 'VerifierApp', 'version': base_version, 'debug': not final_debug}),
        'config/database.xml': f'<database>\n <host>{base_host}</host>\n <port>{base_port}</port>\n</database>\n',
        'config/network/routes.csv': routes_csv(base_rows),
        'config/ignored.txt': 'not part of the report\n',
    })
    add_archive(backups / '01_inc.tar.gz', {
        'config/app.json': json.dumps({'app_name': 'VerifierApp', 'version': final_version, 'debug': final_debug}),
    })
    add_archive(backups / '02_inc.tar.gz', {
        'config/database.xml': f'<database>\n  <host>{final_host}</host>\n  <port>{final_port}</port>\n</database>\n',
        'config/network/routes.csv': routes_csv(final_rows),
    })

    archive_hashes = {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in backups.glob('*.tar.gz')
    }
    if output.exists():
        output.unlink()

    subprocess.run(
        ['runuser', '-u', 'user', '--', 'sh', '-c', 'cd /home/user && /tmp/tracker-verifier'],
        check=True,
        timeout=30,
    )

    assert output.is_file(), 'Program did not generate /home/user/final_state.json'
    with output.open() as f:
        actual = json.load(f)
    expected = {
        'app_version': final_version,
        'app_debug': final_debug,
        'db_host': final_host,
        'db_port': final_port,
        'route_count': route_count,
    }
    assert set(actual) == set(expected), f'Output keys differ: expected {set(expected)}, got {set(actual)}'
    assert actual == expected, f'Dynamic archive result is incorrect: expected {expected}, got {actual}'

    after_hashes = {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in backups.glob('*.tar.gz')
    }
    assert after_hashes == archive_hashes, 'Program modified the backup archives'
    assert not (home / 'config').exists(), 'Program extracted archive contents under /home/user/config'
    assert not Path('/tmp/config').exists(), 'Program extracted archive contents under /tmp/config'
finally:
    if backups.exists():
        shutil.rmtree(backups)
    saved.rename(backups)
    output.write_bytes(fixed_output)
    os.chmod(output, 0o644)
PY
CHECKS
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
