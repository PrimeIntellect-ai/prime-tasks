#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

WORK=$(mktemp -d /tmp/etl-verifier.XXXXXX) || exit 0
chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/check_output.py" <<'PY_EOF'
import os
import sys

raw_path, clean_path = sys.argv[1], sys.argv[2]
records = {}
with open(raw_path, "r") as f:
    for line in f:
        if not line.strip():
            continue
        parts = [p.strip() for p in line.split(',')]
        if len(parts) >= 3 and parts[1].lower() == "max_workers":
            ts = int(parts[0])
            val = int(parts[2])
            if ts not in records or val > records[ts]:
                records[ts] = val

if not records or not os.path.isfile(clean_path):
    sys.exit(1)

expected = ["timestamp,param_name,value,delta"]
current = None
previous = None
for ts in range(min(records), max(records) + 10, 10):
    if ts in records:
        current = records[ts]
    delta = 0 if previous is None else current - previous
    expected.append(f"{ts},max_workers,{current},{delta}")
    previous = current

with open(clean_path, "r") as f:
    actual = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

sys.exit(0 if actual == expected else 1)
PY_EOF

python3 - "$WORK/random_raw.csv" <<'PY_EOF'
import secrets
import sys

path = sys.argv[1]
base = 1800000000 + secrets.randbelow(50000) * 10
values = [secrets.randbelow(30) + 1 for _ in range(6)]
rows = [
    f" {base} , Other_Param , 999 ",
    f"{base}, Max_Workers , {values[0]}",
    f"{base},max_workers,{values[1]}",
    f" {base + 10}, MAX_WORKERS, {values[2]} ",
    f"{base + 20},ignored,123",
    f"{base + 30}, max_Workers ,{values[3]}",
    f"{base + 30},MAX_WORKERS,{values[4]}",
    f"{base + 60}, max_workers , {values[5]}",
]
with open(path, "w") as f:
    f.write("\n".join(rows) + "\n")
PY_EOF

candidates=()
while IFS= read -r -d '' file; do
    case "$file" in
        /home/user/raw_config.csv|/home/user/clean_config.csv) continue ;;
    esac
    first_line=$(head -n 1 "$file" 2>/dev/null)
    case "$file:$first_line" in
        *.sh:*|*:#!*bash*)
            if /bin/bash -n "$file" >/dev/null 2>&1; then
                candidates+=("$file")
            fi
            ;;
    esac
done < <(find /home/user -xdev -type f -print0 2>/dev/null)

winner=""
for candidate in "${candidates[@]}"; do
    rm -f /home/user/raw_config.csv /home/user/clean_config.csv
    cp "$WORK/random_raw.csv" /home/user/raw_config.csv || continue
    chmod 644 /home/user/raw_config.csv

    timeout 15s runuser -u user -- env HOME=/home/user PATH=/usr/local/bin:/usr/bin:/bin \
        /bin/bash -c 'cd /home/user && exec /bin/bash "$1"' bash "$candidate" \
        >/dev/null 2>&1

    if python3 "$WORK/check_output.py" "$WORK/random_raw.csv" /home/user/clean_config.csv; then
        winner="$candidate"
        break
    fi
done

if [ -z "$winner" ]; then
    exit 0
fi

cat > "$WORK/original_raw.csv" <<'EOF'
1710000000, Max_Workers , 5
1710000000,max_workers, 8
1710000010, MAX_WORKERS, 12
1710000010, other_param, 50
1710000040, max_Workers, 10
1710000060, max_workers, 15
1710000060, max_workers, 15
1710000090, max_workers, 14
EOF

rm -f /home/user/raw_config.csv /home/user/clean_config.csv
cp "$WORK/original_raw.csv" /home/user/raw_config.csv || exit 0
chmod 644 /home/user/raw_config.csv

timeout 15s runuser -u user -- env HOME=/home/user PATH=/usr/local/bin:/usr/bin:/bin \
    /bin/bash -c 'cd /home/user && exec /bin/bash "$1"' bash "$winner" \
    >/dev/null 2>&1 || exit 0

cat > "$WORK/test_final_state.py" <<'TEST_EOF'
import os
import pytest

RAW_DATA_PATH = "/home/user/raw_config.csv"
CLEAN_DATA_PATH = "/home/user/clean_config.csv"

def test_clean_config_exists():
    assert os.path.isfile(CLEAN_DATA_PATH), f"Output file {CLEAN_DATA_PATH} is missing."

def test_clean_config_content():
    assert os.path.isfile(RAW_DATA_PATH), f"Input file {RAW_DATA_PATH} is missing."

    records = {}
    with open(RAW_DATA_PATH, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            parts = [p.strip() for p in line.split(',')]
            if len(parts) >= 3:
                ts_str, param, val_str = parts[0], parts[1], parts[2]
                if param.lower() == 'max_workers':
                    ts = int(ts_str)
                    val = int(val_str)
                    if ts not in records or val > records[ts]:
                        records[ts] = val

    if not records:
        pytest.fail("No valid max_workers records found in raw data.")

    min_ts = min(records.keys())
    max_ts = max(records.keys())
    expected_lines = ["timestamp,param_name,value,delta"]
    current_val = None
    prev_val = None

    for ts in range(min_ts, max_ts + 10, 10):
        if ts in records:
            current_val = records[ts]
        if prev_val is None:
            delta = 0
        else:
            delta = current_val - prev_val
        expected_lines.append(f"{ts},max_workers,{current_val},{delta}")
        prev_val = current_val

    expected_content = "\n".join(expected_lines) + "\n"
    with open(CLEAN_DATA_PATH, 'r') as f:
        actual_content = f.read()

    actual_lines = [line.strip() for line in actual_content.strip().split('\n') if line.strip()]
    expected_lines_clean = [line.strip() for line in expected_content.strip().split('\n') if line.strip()]
    assert actual_lines == expected_lines_clean, f"Content of {CLEAN_DATA_PATH} does not match expected output.\nExpected:\n{expected_content}\nActual:\n{actual_content}"
TEST_EOF

if python3 -m pytest "$WORK/test_final_state.py" -x --tb=short >/dev/null 2>&1; then
    echo "1" > /logs/verifier/reward.txt
fi
