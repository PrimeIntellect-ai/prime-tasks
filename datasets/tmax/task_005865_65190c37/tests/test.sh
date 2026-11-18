#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_curate.py
import os
import secrets
import shutil
import subprocess
import threading
import time
from pathlib import Path

HOME = Path('/home/user')
SCRIPT = HOME / 'curate.sh'
LOG = HOME / 'logs/scan.log'
INCOMING = HOME / 'incoming'
BINARIES = HOME / 'repo/binaries'
MANIFEST = HOME / 'repo/manifest.txt'
SUMMARY = HOME / 'curation_summary.log'

# Preserve the original verifier's assertions against the requested final state.
APPROVED_ARTIFACTS = ['auth-v1.bin', 'cache-v4.bin', 'core-v1.bin']
UNAPPROVED_ARTIFACTS = ['db-v3.bin', 'ui-v2.bin']

assert SCRIPT.is_file(), f'Script {SCRIPT} does not exist.'
assert os.access(SCRIPT, os.X_OK), f'Script {SCRIPT} is not executable.'

assert SUMMARY.is_file(), f'Summary log {SUMMARY} does not exist.'
with SUMMARY.open() as f:
    lines = [line.strip() for line in f if line.strip()]
assert lines == APPROVED_ARTIFACTS, f'Summary log contents are incorrect. Expected {APPROVED_ARTIFACTS}, got {lines}'

for artifact in APPROVED_ARTIFACTS:
    assert (BINARIES / artifact).is_file(), f'Approved artifact {artifact} was not moved to {BINARIES}.'
    assert not (INCOMING / artifact).is_file(), f'Approved artifact {artifact} still exists in {INCOMING}.'
for artifact in UNAPPROVED_ARTIFACTS:
    assert not (BINARIES / artifact).is_file(), f'Unapproved artifact {artifact} should not be in {BINARIES}.'
    assert (INCOMING / artifact).is_file(), f'Unapproved artifact {artifact} should still be in {INCOMING}.'

assert MANIFEST.is_file(), f'Manifest file {MANIFEST} does not exist.'
manifest_dict = {}
with MANIFEST.open() as f:
    for line in f:
        parts = [part.strip() for part in line.strip().split('|')]
        if len(parts) >= 2:
            manifest_dict[parts[0]] = parts[1]
for artifact in APPROVED_ARTIFACTS:
    assert manifest_dict.get(artifact) == 'APPROVED', f'Artifact {artifact} status in manifest is not APPROVED.'
for artifact in UNAPPROVED_ARTIFACTS:
    assert manifest_dict.get(artifact) == 'PENDING', f'Artifact {artifact} status in manifest is not PENDING.'
assert manifest_dict.get('legacy-v1.bin') == 'APPROVED', 'legacy-v1.bin status was incorrectly modified.'

# Rebuild the fixture with unpredictable names, then execute the submitted script.
token = secrets.token_hex(8)
records = [
    (f'zeta-{token}.bin', 'SUCCESS', 0, 9),
    (f'alpha-{token}.bin', 'FAILED', 0, 0),
    (f'middle-{token}.bin', 'SUCCESS', 3, 0),
    (f'beta-{token}.bin', 'SUCCESS', 0, 2),
    (f'omega-{token}.bin', 'SUCCESS', 0, 0),
]

log_parts = []
for name, status, critical, warnings in records:
    log_parts.append(
        f'Artifact: {name}\n'
        f'Build-Status: {status}\n'
        f'Critical-Vulnerabilities: {critical}\n'
        f'Warnings: {warnings}\n'
    )
log_text = '---\n'.join(log_parts)

# Independently parse the generated log to derive the expected approvals.
def parse_scan_log(text):
    approved = []
    for raw_record in text.split('---\n'):
        fields = {}
        for raw_line in raw_record.splitlines():
            if ':' in raw_line:
                key, value = raw_line.split(':', 1)
                fields[key.strip()] = value.strip()
        if (fields.get('Build-Status') == 'SUCCESS' and
                fields.get('Critical-Vulnerabilities') == '0'):
            approved.append(fields['Artifact'])
    return sorted(approved)

approved = parse_scan_log(log_text)
all_names = [record[0] for record in records]
unapproved = sorted(set(all_names) - set(approved))

shutil.rmtree(INCOMING, ignore_errors=True)
shutil.rmtree(BINARIES, ignore_errors=True)
INCOMING.mkdir(parents=True)
BINARIES.mkdir(parents=True)
LOG.parent.mkdir(parents=True, exist_ok=True)
LOG.write_text(log_text)
if SUMMARY.exists() or SUMMARY.is_symlink():
    SUMMARY.unlink()

for index, name in enumerate(all_names):
    (INCOMING / name).write_bytes(f'artifact-{token}-{index}\n'.encode())

manifest_lines = []
for i in range(6000):
    manifest_lines.append(f'filler-{token}-{i:05d}.bin | PENDING | {1700000000 + i}\n')
for i, name in enumerate(all_names):
    manifest_lines.append(f'{name} | PENDING | {1800000000 + i}\n')
manifest_lines.append(f'legacy-{token}.bin | APPROVED | 1600000000\n')
old_manifest = ''.join(manifest_lines).encode()
expected_manifest = old_manifest
for name in approved:
    expected_manifest = expected_manifest.replace(
        f'{name} | PENDING |'.encode(), f'{name} | APPROVED |'.encode(), 1
    )
MANIFEST.write_bytes(old_manifest)

# Ensure the submitted user can operate on the recreated fixture.
for path in [HOME / 'logs', INCOMING, HOME / 'repo', BINARIES]:
    os.chmod(path, 0o777)
for path in [LOG, MANIFEST]:
    os.chown(path, 1000, 1000)
    os.chmod(path, 0o666)
for path in INCOMING.iterdir():
    os.chown(path, 1000, 1000)
    os.chmod(path, 0o666)

old_inode = MANIFEST.stat().st_ino
observations = []
stop = threading.Event()

def observe_manifest():
    while not stop.is_set():
        try:
            observations.append(MANIFEST.read_bytes())
        except FileNotFoundError:
            observations.append(None)
        time.sleep(0.0005)

observer = threading.Thread(target=observe_manifest, daemon=True)
observer.start()
try:
    proc = subprocess.run(
        ['/bin/bash', '-c', 'exec /home/user/curate.sh'],
        cwd='/home/user',
        user=1000,
        group=1000,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
finally:
    stop.set()
    observer.join(timeout=2)

assert proc.returncode == 0, (
    f'curate.sh failed with exit code {proc.returncode}: '
    f'{proc.stderr.decode(errors="replace")}'
)

# Final behavioral checks on answers derived from the new scan log.
assert SUMMARY.is_file(), 'curate.sh did not create the summary when executed.'
with SUMMARY.open() as f:
    actual_summary = [line.strip() for line in f if line.strip()]
assert actual_summary == approved, f'Expected summary {approved}, got {actual_summary}'

assert sorted(path.name for path in BINARIES.iterdir()) == approved, 'Repository binaries are incorrect after execution.'
assert sorted(path.name for path in INCOMING.iterdir()) == unapproved, 'Incoming binaries are incorrect after execution.'
assert MANIFEST.read_bytes() == expected_manifest, 'Manifest content was not updated exactly as required.'

# An atomic replacement has a new inode, and readers must see either the complete
# old manifest or the complete new manifest, never absence or partial content.
assert MANIFEST.stat().st_ino != old_inode, 'Manifest was modified in place instead of atomically replaced.'
assert observations, 'No manifest observations were collected.'
assert all(value in (old_manifest, expected_manifest) for value in observations), (
    'A reader observed a missing or partially written manifest; update was not atomic.'
)
PY_EOF

if python3 /tmp/verify_curate.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
