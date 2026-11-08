#!/bin/bash
mkdir -p /logs/verifier
status=0

(
set -e

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def test_rust_project_exists():
    cargo_toml = '/home/user/route-compiler/Cargo.toml'
    assert os.path.isfile(cargo_toml), f'Rust project not found. Expected Cargo.toml at {cargo_toml}'
    assert os.path.isfile('/home/user/route-compiler/src/main.rs'), 'Rust source file src/main.rs is missing.'


def test_merged_txt_content():
    merged_file = '/home/user/merged.txt'
    assert os.path.isfile(merged_file), f'Output file {merged_file} does not exist.'
    expected_lines = [
        'DELETE /api/data [] -> api_delete (Weight: 100)',
        'GET /api/data [filter] -> api_handler (Weight: 50)',
        'POST /login [method] -> legacy_login (Weight: 20)',
        'GET /home [lang] -> home_handler (Weight: 10)'
    ]
    with open(merged_file, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_lines, (
        f'Contents of {merged_file} do not match expected output.\n'
        f'Expected:\n{chr(10).join(expected_lines)}\n'
        f'Actual:\n{chr(10).join(actual_lines)}'
    )


def test_diff_txt_content():
    diff_file = '/home/user/diff.txt'
    assert os.path.isfile(diff_file), f'Output file {diff_file} does not exist.'
    expected_lines = [
        'MODIFIED: GET /api/data',
        'ADDED: POST /login',
        'REMOVED: PUT /upload'
    ]
    with open(diff_file, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_lines, (
        f'Contents of {diff_file} do not match expected output.\n'
        f'Expected:\n{chr(10).join(expected_lines)}\n'
        f'Actual:\n{chr(10).join(actual_lines)}'
    )
TEST_EOF

# Preserve the original final-state assertions.
python3 -m pytest /tmp/test_final_state.py -x --tb=short

# Remove pre-existing outputs, then require the Rust application itself to recreate them.
rm -f /home/user/merged.txt /home/user/diff.txt
(
    cd /home/user/route-compiler
    timeout 120s cargo run --quiet
)
python3 -m pytest /tmp/test_final_state.py -x --tb=short

backup_dir=$(mktemp -d)
cp -a /home/user/routes/. "$backup_dir/"
restore_routes() {
    rm -rf /home/user/routes
    mkdir -p /home/user/routes
    cp -a "$backup_dir/." /home/user/routes/
    rm -rf "$backup_dir"
}
trap restore_routes EXIT

rm -f /home/user/routes/*
cat << 'EOF' > /home/user/routes/one.route
GET /z?b=2&a=1 zed 3
POST /same?x=1 beta 10
POST /same?y=1 alpha 10
PUT /new?c=3&a=1&b=2 new_handler 40
PATCH /mod?q=1 mod_new 7
EOF

cat << 'EOF' > /home/user/routes/two.route
GET /z?c=9 z_high 8
POST /same?k=1 gamma 9
HEAD /plain plain_handler 8
EOF

cat << 'EOF' > /home/user/routes/previous.txt
DELETE /gone [] -> gone_handler (Weight: 1)
GET /z [c] -> z_high (Weight: 8)
HEAD /plain [] -> plain_handler (Weight: 8)
PATCH /mod [q] -> mod_old (Weight: 7)
POST /same [x] -> alpha (Weight: 10)
EOF

# Derive expected results independently from the altered inputs before execution.
cat << 'PY_EOF' > /tmp/make_expected.py
from pathlib import Path
import re

routes_dir = Path('/home/user/routes')
current = {}
for route_file in sorted(routes_dir.glob('*.route')):
    for raw in route_file.read_text().splitlines():
        if not raw.strip():
            continue
        method, full_path, handler, weight_text = raw.split()
        weight = int(weight_text)
        base, sep, query = full_path.partition('?')
        params = []
        if sep and query:
            params = sorted(part.split('=', 1)[0] for part in query.split('&') if part)
        key = (method, base)
        candidate = (handler, weight, params)
        old = current.get(key)
        if old is None or weight > old[1] or (weight == old[1] and handler < old[0]):
            current[key] = candidate

previous = {}
pattern = re.compile(r'^(\S+) (\S+) \[(.*)\] -> (\S+) \(Weight: (-?\d+)\)$')
for raw in (routes_dir / 'previous.txt').read_text().splitlines():
    if not raw.strip():
        continue
    match = pattern.fullmatch(raw.strip())
    assert match, f'Invalid previous route in test fixture: {raw}'
    method, base, param_text, handler, weight_text = match.groups()
    params = [] if not param_text else [p.strip() for p in param_text.split(',')]
    previous[(method, base)] = (handler, int(weight_text), params)

merged = []
for (method, base), (handler, weight, params) in sorted(
    current.items(), key=lambda item: (-item[1][1], item[0][0], item[0][1])
):
    merged.append(f'{method} {base} [{", ".join(params)}] -> {handler} (Weight: {weight})')

diff = []
for method, base in sorted(set(current) | set(previous)):
    key = (method, base)
    if key not in previous:
        status = 'ADDED'
    elif key not in current:
        status = 'REMOVED'
    elif current[key] != previous[key]:
        status = 'MODIFIED'
    else:
        continue
    diff.append(f'{status}: {method} {base}')

Path('/tmp/expected_merged.txt').write_text('\n'.join(merged) + '\n')
Path('/tmp/expected_diff.txt').write_text('\n'.join(diff) + '\n')
PY_EOF
python3 /tmp/make_expected.py

rm -f /home/user/merged.txt /home/user/diff.txt
(
    cd /home/user/route-compiler
    timeout 120s cargo run --quiet
)

test -f /home/user/merged.txt
test -f /home/user/diff.txt
cmp -s /tmp/expected_merged.txt /home/user/merged.txt
cmp -s /tmp/expected_diff.txt /home/user/diff.txt
) || status=$?

if [ "$status" -eq 0 ]; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
