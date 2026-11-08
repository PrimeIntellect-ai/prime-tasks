#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from decimal import Decimal
from pathlib import Path

DATA = Path('/home/user/data.csv')
OUTPUT = Path('/home/user/optimal_params.txt')
EXPECTED_ORIGINAL = 'm=2.00, b=1.10, SSE=0.09'


def find_scripts():
    candidates = []
    excluded = {DATA.resolve(), OUTPUT.resolve()}
    for root in ('/home/user', '/root', '/tmp'):
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in {'.cache', '.local', '__pycache__'}]
            for name in filenames:
                path = Path(dirpath) / name
                try:
                    resolved = path.resolve()
                    if resolved in excluded or not path.is_file() or path.stat().st_size > 1024 * 1024:
                        continue
                    raw = path.read_bytes()
                    if b'\x00' in raw:
                        continue
                    text = raw.decode('utf-8', errors='ignore')
                except (OSError, ValueError):
                    continue
                first = text.splitlines()[0] if text.splitlines() else ''
                looks_like_bash = (
                    name.endswith(('.sh', '.bash'))
                    or ('#!' in first and ('bash' in first or first.rstrip().endswith('/sh')))
                    or ('/home/user/data.csv' in text and '/home/user/optimal_params.txt' in text)
                )
                if looks_like_bash:
                    candidates.append(path)
    return sorted(set(candidates), key=lambda p: (str(p).count('/'), str(p)))


def optimum(rows):
    best = None
    winners = []
    for mi in range(51):
        m = Decimal(mi) / Decimal(10)
        for bi in range(51):
            b = Decimal(bi) / Decimal(10)
            sse = sum((y - (m * x + b)) ** 2 for x, y in rows)
            if best is None or sse < best:
                best = sse
                winners = [(m, b)]
            elif sse == best:
                winners.append((m, b))
    return best, winners


def make_case():
    while True:
        mi = secrets.randbelow(41) + 5
        bi = secrets.randbelow(41) + 5
        m = Decimal(mi) / Decimal(10)
        b = Decimal(bi) / Decimal(10)
        rows = []
        for x_int in range(1, 8):
            x = Decimal(x_int)
            noise = Decimal(secrets.randbelow(61) - 30) / Decimal(100)
            y = m * x + b + noise
            rows.append((x, y))
        best, winners = optimum(rows)
        if len(winners) == 1:
            wm, wb = winners[0]
            expected = f'm={float(wm):.2f}, b={float(wb):.2f}, SSE={float(best):.2f}'
            csv = ''.join(f'{x},{y}\n' for x, y in rows)
            return csv, expected


def run_case(script, csv, expected):
    DATA.write_text(csv)
    try:
        OUTPUT.unlink()
    except FileNotFoundError:
        pass
    result = subprocess.run(
        ['/bin/bash', str(script)],
        cwd=str(script.parent),
        env={**os.environ, 'HOME': '/home/user'},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=90,
    )
    if result.returncode != 0:
        return False, f'exited with status {result.returncode}: {result.stderr[-500:]}'
    if not OUTPUT.is_file():
        return False, 'did not create /home/user/optimal_params.txt'
    actual = OUTPUT.read_text().strip()
    if actual != expected:
        return False, f'expected {expected!r}, found {actual!r}'
    return True, ''


def main():
    # Preserve the original verifier's assertions.
    assert OUTPUT.is_file(), (
        'The file /home/user/optimal_params.txt does not exist. '
        'Make sure your script creates it.'
    )
    content = OUTPUT.read_text().strip()
    assert content == EXPECTED_ORIGINAL, (
        'The content of /home/user/optimal_params.txt is incorrect.\n'
        f"Expected: '{EXPECTED_ORIGINAL}'\nFound: '{content}'\n"
        'Check your grid search logic, SSE calculation, and formatting.'
    )

    original_data = DATA.read_bytes()
    original_output = OUTPUT.read_bytes()
    try:
        scripts = find_scripts()
        assert scripts, 'No Bash script implementing the requested grid search was found.'
        cases = [make_case(), make_case()]
        failures = []
        for script in scripts:
            passed = True
            for csv, expected in cases:
                try:
                    ok, reason = run_case(script, csv, expected)
                except subprocess.TimeoutExpired:
                    ok, reason = False, 'timed out'
                except OSError as exc:
                    ok, reason = False, str(exc)
                if not ok:
                    failures.append(f'{script}: {reason}')
                    passed = False
                    break
            if passed:
                return
        raise AssertionError(
            'No submitted Bash script correctly recomputed the grid-search result '
            'for verification datasets. ' + ' | '.join(failures[-5:])
        )
    finally:
        DATA.write_bytes(original_data)
        OUTPUT.write_bytes(original_output)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
