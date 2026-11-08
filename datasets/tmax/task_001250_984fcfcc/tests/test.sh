#!/bin/bash
mkdir -p /logs/verifier

verify() {
    python3 - <<'PY' || return 1
import os
import stat
p = "/home/user/organize.sh"
assert os.path.exists(p), f"Script {p} does not exist."
assert stat.S_ISREG(os.lstat(p).st_mode), f"{p} is not a regular file."
assert os.stat(p).st_mode & stat.S_IXUSR, f"Script {p} is not executable by the user."
PY

    mkdir -p /home/user/raw_data || return 1
    cat > /home/user/raw_data/alpha.json <<'EOF' || return 1
[
  {"timestamp": 1620000000, "sensor": "A", "reading": 45.2},
  {"timestamp": 1620000060, "sensor": "A", "reading": 46.1}
]
EOF

    cat > /home/user/raw_data/beta.csv <<'EOF' || return 1
timestamp,sensor,reading
1620000120,B,42.8
1620000180,B,43.0
EOF

    cat > /home/user/dataset_pipeline.conf <<'EOF' || return 1
# Pipeline Configuration
/home/user/raw_data/alpha.json|/home/user/clean_data/alpha_exp|results.csv|csv|true
/home/user/raw_data/beta.csv|/home/user/clean_data/beta_exp|results.csv|csv|false
EOF

    rm -rf /home/user/clean_data || return 1
    timeout 20s runuser -u user -- env HOME=/home/user bash -c 'cd /home/user && exec /home/user/organize.sh' || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py || return 1
# test_final_state.py

import os
import stat
import csv

def test_script_exists_and_executable():
    script_path = "/home/user/organize.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a regular file."
    st = os.stat(script_path)
    assert st.st_mode & stat.S_IXUSR, f"Script {script_path} is not executable by the user."

def test_directories_created():
    alpha_dir = "/home/user/clean_data/alpha_exp"
    beta_dir = "/home/user/clean_data/beta_exp"
    assert os.path.isdir(alpha_dir), f"Directory {alpha_dir} does not exist."
    assert os.path.isdir(beta_dir), f"Directory {beta_dir} does not exist."

def test_json_to_csv_conversion():
    csv_path = "/home/user/clean_data/alpha_exp/results.csv"
    assert os.path.exists(csv_path), f"File {csv_path} does not exist."
    assert os.path.isfile(csv_path), f"{csv_path} is not a regular file."

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) >= 3, f"{csv_path} should have a header and at least 2 rows of data."

    # Check headers
    header = [col.strip('"\' ') for col in rows[0]]
    assert set(header) == {"timestamp", "sensor", "reading"}, f"Header row in {csv_path} does not match expected keys."

    # Check data content
    data_str = " ".join("".join(row) for row in rows[1:])
    assert "1620000000" in data_str, "Missing timestamp 1620000000 in CSV."
    assert "45.2" in data_str, "Missing reading 45.2 in CSV."
    assert "1620000060" in data_str, "Missing timestamp 1620000060 in CSV."
    assert "46.1" in data_str, "Missing reading 46.1 in CSV."
    assert "A" in data_str.replace('"', ''), "Missing sensor A in CSV."

def test_hardlink_created():
    source_path = "/home/user/raw_data/beta.csv"
    target_path = "/home/user/clean_data/beta_exp/results.csv"

    assert os.path.exists(source_path), f"Source file {source_path} is missing."
    assert os.path.exists(target_path), f"Target file {target_path} does not exist."

    stat_source = os.stat(source_path)
    stat_target = os.stat(target_path)

    assert stat_source.st_ino == stat_target.st_ino, f"{target_path} is not a hard link to {source_path} (inodes differ)."

def test_symlink_latest_dataset():
    symlink_path = "/home/user/clean_data/latest_dataset"
    expected_target = "/home/user/clean_data/alpha_exp"

    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."
    actual_target = os.readlink(symlink_path)
    assert actual_target == expected_target, f"Symlink points to {actual_target}, expected {expected_target}."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1

    TOKEN=$(python3 -c 'import secrets; print(secrets.token_hex(10))') || return 1
    ROOT="/home/user/pipeline_test_${TOKEN}"
    SRC_DIR="$ROOT/source"
    JSON_DIR="$ROOT/generated_json"
    CSV_DIR="$ROOT/generated_csv"
    JSON_SRC="$SRC_DIR/input_${TOKEN}.json"
    CSV_SRC="$SRC_DIR/input_${TOKEN}.csv"
    JSON_NAME="converted_${TOKEN}.csv"
    CSV_NAME="linked_${TOKEN}.csv"

    export TOKEN ROOT SRC_DIR JSON_DIR CSV_DIR JSON_SRC CSV_SRC JSON_NAME CSV_NAME
    mkdir -p "$SRC_DIR" "$CSV_DIR" || return 1

    python3 - <<'PY' || return 1
import csv
import json
import os
import secrets

token = os.environ["TOKEN"]
base = secrets.randbelow(800000) + 100000
records = [
    {"event_id": base, "device": "unit," + token, "measurement": 17.375},
    {"event_id": base + 9, "device": "unit-" + token, "measurement": 91.625},
]
with open(os.environ["JSON_SRC"], "w") as f:
    json.dump(records, f)
with open(os.environ["CSV_SRC"], "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["nonce", "value"])
    w.writerow([token, secrets.token_hex(8)])
PY

    printf 'stale destination\n' > "$CSV_DIR/$CSV_NAME" || return 1
    chown -R user:user "$ROOT" || return 1

    cat > /home/user/dataset_pipeline.conf <<EOF || return 1
# Randomized pipeline configuration

$JSON_SRC|$JSON_DIR|$JSON_NAME|csv|true
$CSV_SRC|$CSV_DIR|$CSV_NAME|csv|true
EOF
    chown user:user /home/user/dataset_pipeline.conf || return 1

    timeout 20s runuser -u user -- env HOME=/home/user bash -c 'cd /home/user && exec /home/user/organize.sh' || return 1

    python3 - <<'PY' || return 1
import csv
import json
import os
import stat

json_src = os.environ["JSON_SRC"]
csv_src = os.environ["CSV_SRC"]
json_target = os.path.join(os.environ["JSON_DIR"], os.environ["JSON_NAME"])
csv_target = os.path.join(os.environ["CSV_DIR"], os.environ["CSV_NAME"])
latest = "/home/user/clean_data/latest_dataset"

assert os.path.isdir(os.environ["JSON_DIR"]), "Script did not create the randomized JSON target directory"
assert os.path.isfile(json_target), "Script did not create the randomized converted CSV"
with open(json_src) as f:
    source_rows = json.load(f)
with open(json_target, newline="") as f:
    reader = csv.DictReader(f)
    assert reader.fieldnames == list(source_rows[0].keys()), "Converted CSV header does not match JSON keys"
    actual_rows = list(reader)
expected_rows = [{k: str(v) for k, v in row.items()} for row in source_rows]
assert actual_rows == expected_rows, "Converted CSV rows do not match the randomized JSON input"

src_stat = os.stat(csv_src)
target_stat = os.stat(csv_target)
assert stat.S_ISREG(target_stat.st_mode), "Randomized hard-link target is not a regular file"
assert (src_stat.st_dev, src_stat.st_ino) == (target_stat.st_dev, target_stat.st_ino), "Existing target was not overwritten with a hard link"

assert os.path.islink(latest), "latest_dataset was not maintained as a symbolic link"
assert os.readlink(latest) == os.environ["CSV_DIR"], "latest_dataset was not updated for the later true entry"
PY
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
