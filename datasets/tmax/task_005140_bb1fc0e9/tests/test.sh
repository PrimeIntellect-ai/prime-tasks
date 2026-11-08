#!/bin/bash
set -u
mkdir -p /logs/verifier

verify_task() {
    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

INCOMING_DIR = "/home/user/incoming"
OUTPUT_FILE = "/home/user/processed_dev01.csv"

def test_deduplication_completed():
    expected_files = ["A.dat", "B.dat", "D.dat"]
    for f in expected_files:
        filepath = os.path.join(INCOMING_DIR, f)
        assert os.path.isfile(filepath), f"Expected file {filepath} to exist, but it is missing."

    deleted_file = os.path.join(INCOMING_DIR, "C.dat")
    assert not os.path.exists(deleted_file), f"Duplicate file {deleted_file} was not deleted."

def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} was not created."

def test_output_file_contents():
    expected_content = [
        "0,20",
        "1,20",
        "2,18",
        "3,18",
        "4,25"
    ]

    with open(OUTPUT_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_content, (
        f"Contents of {OUTPUT_FILE} do not match expected output.\n"
        f"Expected: {expected_content}\n"
        f"Got: {lines}"
    )
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    # Locate a persistent Bash driver so the submitted workflow can be exercised
    # on data that was not present when the agent ran.
    candidates=()
    while IFS= read -r -d '' file; do
        case "$file" in
            /home/user/incoming/*|/home/user/processed_dev01.csv|/tmp/test_final_state.py|/tmp/verifier_*) continue ;;
        esac
        if grep -Iq . "$file" 2>/dev/null \
           && grep -q 'incoming' "$file" 2>/dev/null \
           && grep -q 'processed_dev01' "$file" 2>/dev/null; then
            first_line=$(head -n 1 "$file" 2>/dev/null || true)
            if [[ "$file" == *.sh || "$first_line" == '#!'*bash* || "$first_line" == '#!'*'/sh'* ]]; then
                candidates+=("$file")
            fi
        fi
    done < <(find /home/user /home/oai/share /tmp /root -type f -print0 2>/dev/null)

    [ "${#candidates[@]}" -gt 0 ] || return 1

    rm -rf /tmp/verifier_fixture
    mkdir -p /tmp/verifier_fixture
    python3 - <<'PY'
import os
import secrets

base = 1672531200
r = secrets.SystemRandom()
v0a = r.randint(31, 70)
v0b = r.randint(81, 120)
v1 = r.randint(131, 170)
v3a = r.randint(181, 220)
v3b = r.randint(221, 260)

files = {
    "kappa.dat": [
        f"{base + 17},DEV01,{v0a}",
        f"{base + 3599},DEV01,{v0b}",
        f"{base + 100},DEV99,9999",
    ],
    "middle.dat": [
        f"{base + 3600},DEV01,{v1}",
        f"{base + 3700},DEV02,8888",
    ],
    "solo.dat": [
        f"{base + 3*3600 + 5},DEV01,{v3a}",
        f"{base + 3*3600 + 2500},DEV01,{v3b}",
    ],
}
files["omega.dat"] = list(files["kappa.dat"])

for name, rows in files.items():
    with open(os.path.join("/tmp/verifier_fixture", name), "w") as f:
        f.write("\n".join(rows) + "\n")
PY

    validate_dynamic() {
        python3 - <<'PY'
import hashlib
import os

fixture = "/tmp/verifier_fixture"
incoming = "/home/user/incoming"
outfile = "/home/user/processed_dev01.csv"
start = 1672531200

# Independently derive which alphabetically first files should remain.
kept = []
seen = set()
for name in sorted(n for n in os.listdir(fixture) if n.endswith(".dat")):
    data = open(os.path.join(fixture, name), "rb").read()
    digest = hashlib.md5(data).digest()
    if digest not in seen:
        seen.add(digest)
        kept.append(name)

actual_files = sorted(n for n in os.listdir(incoming) if n.endswith(".dat"))
assert actual_files == kept, (actual_files, kept)

maxima = [None] * 5
for name in kept:
    with open(os.path.join(fixture, name)) as f:
        for raw in f:
            timestamp, device, value = raw.strip().split(",")
            timestamp = int(timestamp)
            value = int(value)
            if device != "DEV01" or not (start <= timestamp < start + 5 * 3600):
                continue
            interval = (timestamp - start) // 3600
            if maxima[interval] is None or value > maxima[interval]:
                maxima[interval] = value

expected = []
previous = 0
for interval, value in enumerate(maxima):
    if value is None:
        value = previous
    previous = value
    expected.append(f"{interval},{value}")

assert os.path.isfile(outfile), "workflow did not create processed_dev01.csv"
with open(outfile) as f:
    actual = [line.strip() for line in f if line.strip()]
assert actual == expected, (actual, expected)
PY
    }

    for candidate in "${candidates[@]}"; do
        candidate_dir=$(dirname "$candidate")
        for run_dir in "$candidate_dir" /home/user; do
            rm -rf /home/user/incoming
            mkdir -p /home/user/incoming
            cp -a /tmp/verifier_fixture/. /home/user/incoming/
            rm -f /home/user/processed_dev01.csv

            if (cd "$run_dir" && timeout 20s bash "$candidate") >/tmp/verifier_run.log 2>&1 \
               && validate_dynamic >/tmp/verifier_validation.log 2>&1; then
                return 0
            fi
        done
    done

    return 1
}

if verify_task; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
