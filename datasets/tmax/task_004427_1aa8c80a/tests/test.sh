#!/bin/bash
set -u
mkdir -p /logs/verifier
reward=0

cat > /tmp/check_original.py <<'PY'
import os

path = "/home/user/final_report.txt"
assert os.path.isfile(path), f"Final report file is missing at {path}"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

assert "=== NETWORK LATENCY REPORT ===" in content, "Report is missing the header."
assert "Date: 2023-10-25" in content, "Report is missing the date."
assert "------------------------------" in content, "Report is missing the separator."
assert "==============================" in content, "Report is missing the footer."
assert "{{REPORTS}}" not in content, "The {{REPORTS}} placeholder was not replaced."
assert "ServerAlpha: 48.00 ms" in content, "ServerAlpha mean is incorrect or missing."
assert "ServerBeta: 100.00 ms" in content, "ServerBeta mean is incorrect or missing."
assert "ServerGamma: 89.15 ms" in content, "ServerGamma mean is incorrect or missing."
PY

if ! python3 /tmp/check_original.py; then
    echo 0 > /logs/verifier/reward.txt
    exit 0
fi

mapfile -d '' sources < <(find /home/user -type f \( -iname '*.cpp' -o -iname '*.cc' -o -iname '*.cxx' \) -print0 2>/dev/null)
if [ "${#sources[@]}" -eq 0 ]; then
    echo 0 > /logs/verifier/reward.txt
    exit 0
fi

cat > /tmp/make_dynamic_case.py <<'PY'
import json
import random
import secrets
from pathlib import Path

rng = random.SystemRandom()
a = rng.randint(20, 180)
b = rng.randint(200, 500)
g = rng.randint(40, 300)
t = rng.randint(1700000000, 1900000000)
token = secrets.token_hex(12)

csv_text = (
    "Timestamp,ServerAlpha,ServerBeta,ServerGamma\n"
    f"{t},{a},-3,{g + 0.25:.2f}\n"
    f"{t+60},{a+10},{b},1001\n"
    f"{t+120},1001,{b+2},{g + 0.75:.2f}\n"
    f"{t+180},-1,{b+4},{g + 1.25:.2f}\n"
)
raw = Path('/home/user/raw_metrics.csv')
raw.write_bytes(csv_text.encode('utf-16le'))

# Support solutions that used iconv as a separate preprocessing command.
utf8_helper = Path('/home/user/raw_metrics_utf8.csv')
utf8_helper.write_text(csv_text, encoding='utf-8')
for p in Path('/home/user').rglob('*.csv'):
    if p not in (raw, utf8_helper) and p.is_file():
        try:
            p.write_text(csv_text, encoding='utf-8')
        except OSError:
            pass

prefix = (
    "=== NETWORK LATENCY REPORT ===\n"
    f"Audit token: {token}\n"
    "Date: dynamic verification\n"
    "------------------------------\n"
)
suffix = "\n==============================\n"
template = prefix + "{{REPORTS}}" + suffix
Path('/home/user/report_template.txt').write_text(template, encoding='utf-8')

meta = {
    'prefix': prefix,
    'suffix': suffix,
    'expected': {
        'ServerAlpha': f'{a + 5:.2f}',
        'ServerBeta': f'{b + 2:.2f}',
        'ServerGamma': f'{g + 0.75:.2f}',
    },
}
Path('/tmp/dynamic_meta.json').write_text(json.dumps(meta), encoding='utf-8')
try:
    Path('/home/user/final_report.txt').unlink()
except FileNotFoundError:
    pass
PY

cat > /tmp/check_dynamic.py <<'PY'
import json
import re
from pathlib import Path

report_path = Path('/home/user/final_report.txt')
assert report_path.is_file(), 'The pipeline did not create final_report.txt'
content = report_path.read_text(encoding='utf-8')
meta = json.loads(Path('/tmp/dynamic_meta.json').read_text(encoding='utf-8'))
prefix, suffix = meta['prefix'], meta['suffix']
assert '{{REPORTS}}' not in content, 'The placeholder remains in the report'
assert content.startswith(prefix), 'The dynamically supplied template prefix was not preserved'
assert content.endswith(suffix), 'The dynamically supplied template suffix was not preserved'

middle = content[len(prefix):len(content)-len(suffix)].strip('\r\n')
lines = middle.splitlines()
assert len(lines) == 3, f'Expected exactly three server report lines, got {lines!r}'
found = {}
pat = re.compile(r'^(ServerAlpha|ServerBeta|ServerGamma): ([0-9]+\.[0-9]{2}) ms$')
for line in lines:
    match = pat.fullmatch(line)
    assert match, f'Incorrect report-line format: {line!r}'
    assert match.group(1) not in found, f'Duplicate server line: {match.group(1)}'
    found[match.group(1)] = match.group(2)
assert found == meta['expected'], f'Incorrect dynamically calculated averages: {found!r}'
PY

candidates=()
all_binary=/tmp/verifier_pipeline_all
if g++ -std=c++17 -O2 "${sources[@]}" -o "$all_binary" >/tmp/verifier_compile.log 2>&1; then
    candidates+=("$all_binary")
fi

idx=0
for src in "${sources[@]}"; do
    bin="/tmp/verifier_pipeline_$idx"
    if g++ -std=c++17 -O2 "$src" -o "$bin" >/tmp/verifier_compile_$idx.log 2>&1; then
        candidates+=("$bin")
    fi
    idx=$((idx+1))
done

for bin in "${candidates[@]}"; do
    # First exercise the common hard-coded-path interface.
    if python3 /tmp/make_dynamic_case.py && timeout 20s "$bin" >/tmp/verifier_run.log 2>&1; then
        if python3 /tmp/check_dynamic.py; then
            reward=1
            break
        fi
    fi

    # Also support a conventional input/template/output command-line interface.
    if python3 /tmp/make_dynamic_case.py && timeout 20s "$bin" /home/user/raw_metrics.csv /home/user/report_template.txt /home/user/final_report.txt >/tmp/verifier_run.log 2>&1; then
        if python3 /tmp/check_dynamic.py; then
            reward=1
            break
        fi
    fi

    # Support programs intended to consume an explicitly iconv-converted file.
    if python3 /tmp/make_dynamic_case.py && timeout 20s "$bin" /home/user/raw_metrics_utf8.csv /home/user/report_template.txt /home/user/final_report.txt >/tmp/verifier_run.log 2>&1; then
        if python3 /tmp/check_dynamic.py; then
            reward=1
            break
        fi
    fi
done

echo "$reward" > /logs/verifier/reward.txt
exit 0
