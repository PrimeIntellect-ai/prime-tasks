#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_pipeline.py
import hashlib
import json
import math
import os
import re
import stat
import subprocess

HOME = "/home/user"
SCRIPT = os.path.join(HOME, "validate_pipeline.sh")
REPORT = os.path.join(HOME, "report.txt")
SIGNAL = os.path.join(HOME, "signal.dat")
FFT = os.path.join(HOME, "fft.py")
LEGACY = os.path.join(HOME, "legacy_fft.out")
MODEL = os.path.join(HOME, "analytical_model.py")
FIXTURE = "/tmp/verifier_signal.tsv"
FFT_LOG = "/tmp/verifier_fft_calls.jsonl"
MODEL_LOG = "/tmp/verifier_model_calls.jsonl"
TRACE = "/tmp/verifier_pipeline.trace"

# Preserve the original verifier's script assertions.
assert os.path.isfile(SCRIPT), f"Script missing: {SCRIPT}"
assert os.access(SCRIPT, os.X_OK), f"Script is not executable: {SCRIPT}"

with open(SCRIPT, "r", errors="replace") as f:
    script_text = f.read()
assert re.search(r"(?<![A-Za-z0-9_])g?awk(?![A-Za-z0-9_])", script_text), \
    "validate_pipeline.sh does not invoke awk"

paths = [SIGNAL, FFT, LEGACY, MODEL]
backups = {}
for path in paths:
    with open(path, "rb") as f:
        backups[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))

# A deterministic verification signal lets the wrappers distinguish the baseline
# call from all bootstrap calls without trusting a pre-existing report.
fixture_lines = []
for i in range(1000):
    t = i / 100.0
    y = math.sin(2.0 * math.pi * 2.45 * t) + 0.1 * math.cos(2.0 * math.pi * 0.7 * t)
    fixture_lines.append(f"{t:.4f} {y:.6f}\n")
fixture_data = "".join(fixture_lines)
with open(FIXTURE, "w") as f:
    f.write(fixture_data)

fft_wrapper = r'''#!/usr/bin/env python3
import hashlib
import json
import sys

fixture_path = "/tmp/verifier_signal.tsv"
log_path = "/tmp/verifier_fft_calls.jsonl"
raw = sys.stdin.read()
valid = True
kind = "invalid"
min_delta = None
max_delta = None
try:
    with open(fixture_path) as f:
        base = [[float(x) for x in line.split()] for line in f if line.strip()]
    rows = [[float(x) for x in line.split()] for line in raw.splitlines() if line.strip()]
    valid = len(rows) == len(base) and all(len(r) == 2 for r in rows)
    if valid:
        deltas = []
        for row, original in zip(rows, base):
            if abs(row[0] - original[0]) > 1e-10:
                valid = False
            deltas.append(row[1] - original[1])
        min_delta = min(deltas)
        max_delta = max(deltas)
        if valid and all(abs(d) <= 1e-10 for d in deltas):
            kind = "baseline"
        elif valid and all(-0.500001 <= d <= 0.500001 for d in deltas) and any(abs(d) > 1e-10 for d in deltas):
            kind = "bootstrap"
        else:
            valid = False
    if kind == "baseline":
        output = "2.450"
    else:
        value = 2.0 + (int(hashlib.sha256(raw.encode()).hexdigest()[:12], 16) % 1000) / 1000.0
        output = f"{value:.3f}"
except Exception:
    valid = False
    output = "9.999"
record = {"kind": kind, "valid": valid, "min_delta": min_delta,
          "max_delta": max_delta, "output": output}
with open(log_path, "a") as f:
    f.write(json.dumps(record) + "\n")
print(output)
'''

model_wrapper = r'''#!/usr/bin/env python3
import json
import sys
log_path = "/tmp/verifier_model_calls.jsonl"
arg = sys.argv[1] if len(sys.argv) > 1 else None
with open(log_path, "a") as f:
    f.write(json.dumps({"arg": arg}) + "\n")
try:
    x = float(arg)
except Exception:
    x = None
if x == 1.0:
    print("10.0")
elif x == 1.00000001:
    print("100000010.0")
else:
    print("0.0")
'''

try:
    with open(SIGNAL, "w") as f:
        f.write(fixture_data)
    with open(LEGACY, "w") as f:
        f.write("2.450\n")
    with open(FFT, "w") as f:
        f.write(fft_wrapper)
    with open(MODEL, "w") as f:
        f.write(model_wrapper)
    os.chmod(FFT, 0o755)
    os.chmod(MODEL, 0o755)

    for path in (FFT_LOG, MODEL_LOG, TRACE, REPORT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ["/bin/bash", "-x", SCRIPT], cwd=HOME,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=120
    )
    with open(TRACE, "w") as f:
        f.write(result.stderr)
    assert result.returncode == 0, \
        f"validate_pipeline.sh failed with exit code {result.returncode}:\n{result.stderr[-2000:]}"
finally:
    for path, (data, mode) in backups.items():
        with open(path, "wb") as f:
            f.write(data)
        os.chmod(path, mode)

with open(TRACE, "r", errors="replace") as f:
    trace = f.read()
assert re.search(r"(?:^|\s)(?:(?:/usr/bin/|/bin/)?g?awk)(?=\s)", trace, re.MULTILINE), \
    "No awk invocation was observed while executing validate_pipeline.sh"

assert os.path.isfile(FFT_LOG), "fft.py was not executed"
with open(FFT_LOG) as f:
    fft_calls = [json.loads(line) for line in f if line.strip()]
assert len(fft_calls) == 101, \
    f"Expected exactly 101 fft.py executions (1 baseline + 100 bootstrap), got {len(fft_calls)}"
assert all(call["valid"] for call in fft_calls), "fft.py received malformed or out-of-range data"
baseline_calls = [call for call in fft_calls if call["kind"] == "baseline"]
bootstrap_calls = [call for call in fft_calls if call["kind"] == "bootstrap"]
assert len(baseline_calls) == 1, f"Expected one baseline FFT call, got {len(baseline_calls)}"
assert len(bootstrap_calls) == 100, f"Expected 100 bootstrap FFT calls, got {len(bootstrap_calls)}"
assert min(call["min_delta"] for call in bootstrap_calls) < 0, "Bootstrap noise never included a negative perturbation"
assert max(call["max_delta"] for call in bootstrap_calls) > 0, "Bootstrap noise never included a positive perturbation"

assert os.path.isfile(MODEL_LOG), "analytical_model.py was not executed"
with open(MODEL_LOG) as f:
    model_calls = [json.loads(line)["arg"] for line in f if line.strip()]
assert model_calls == ["1.0", "1.00000001"], \
    f"Expected analytical model calls at 1.0 and 1.00000001, got {model_calls}"

# Preserve the original verifier's report assertions.
assert os.path.isfile(REPORT), f"Report missing: {REPORT}"
with open(REPORT, "r") as f:
    content = f.read()
assert "REGRESSION: PASS" in content, "Expected 'REGRESSION: PASS' in report.txt"
assert "STABILITY: FAIL" in content, "Expected 'STABILITY: FAIL' in report.txt"
match = re.search(r"BOOTSTRAP_CI_90:\s*\[\s*\d+\.\d+\s*,\s*\d+\.\d+\s*\]", content)
assert match is not None, "BOOTSTRAP_CI_90 format is incorrect or missing in report.txt"

lines = content.splitlines()
assert len(lines) == 3, f"report.txt must contain exactly three lines, got {len(lines)}"
assert lines[0] == "REGRESSION: PASS", "Incorrect regression result or report format"
assert lines[2] == "STABILITY: FAIL", "Incorrect stability result or report format"
ci_match = re.fullmatch(r"BOOTSTRAP_CI_90: \[([0-9]+\.[0-9]+), ([0-9]+\.[0-9]+)\]", lines[1])
assert ci_match, "Confidence interval line does not match the required exact format"
reported_lower = float(ci_match.group(1))
reported_upper = float(ci_match.group(2))
values = sorted(float(call["output"]) for call in bootstrap_calls)
expected_lower = values[4]
expected_upper = values[94]
assert abs(reported_lower - expected_lower) < 1e-9, \
    f"Incorrect lower CI bound: expected {expected_lower}, got {reported_lower}"
assert abs(reported_upper - expected_upper) < 1e-9, \
    f"Incorrect upper CI bound: expected {expected_upper}, got {reported_upper}"
PY_EOF

python3 /tmp/verify_pipeline.py
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
