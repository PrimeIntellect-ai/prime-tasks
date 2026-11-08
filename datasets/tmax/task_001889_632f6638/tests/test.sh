#!/bin/bash
mkdir -p /logs/verifier

ORIG_EMBED=/tmp/verifier_original_mock_embed
EMBED_PATH=/usr/local/bin/mock_embed
STATE_DIR=/tmp/verifier_embed_state
rm -rf "$STATE_DIR" "$ORIG_EMBED"
mkdir -p "$STATE_DIR"
printf '0\n' > "$STATE_DIR/seq"
printf '0\n' > "$STATE_DIR/active"
: > "$STATE_DIR/events.tsv"
: > "$STATE_DIR/boundaries.tsv"

if [ -e "$EMBED_PATH" ] || [ -L "$EMBED_PATH" ]; then
    mv "$EMBED_PATH" "$ORIG_EMBED"
fi

cleanup() {
    rm -f "$EMBED_PATH"
    if [ -e "$ORIG_EMBED" ] || [ -L "$ORIG_EMBED" ]; then
        mv "$ORIG_EMBED" "$EMBED_PATH"
    fi
}
trap cleanup EXIT

cat > "$EMBED_PATH" <<'WRAPPER_EOF'
#!/bin/bash
state=/tmp/verifier_embed_state
file=$1

exec 9>"$state/lock"
flock 9
seq=$(cat "$state/seq")
seq=$((seq + 1))
printf '%s\n' "$seq" > "$state/seq"
active=$(cat "$state/active")
active_before=$active
active=$((active + 1))
printf '%s\n' "$active" > "$state/active"

if [ "$seq" -eq 1 ] || [ "$seq" -eq 51 ] || [ "$seq" -eq 101 ]; then
    count=$(python3 - <<'PY'
import sqlite3
try:
    con = sqlite3.connect('/home/user/dataset.db', timeout=2)
    row = con.execute('SELECT count(*) FROM documents').fetchone()
    print(row[0])
    con.close()
except Exception:
    print(-1)
PY
)
    printf '%s\t%s\t%s\n' "$seq" "$count" "$active_before" >> "$state/boundaries.tsv"
fi

start=$(date +%s%N)
printf 'START\t%s\t%s\t%s\t%s\n' "$seq" "$(basename -- "$file")" "$start" "$active" >> "$state/events.tsv"
flock -u 9

sleep 0.05
len=$(wc -c < "$file")
status=$?
if [ "$status" -eq 0 ]; then
    printf '[%s, 0.5, -0.1]\n' "$len"
fi

flock 9
active=$(cat "$state/active")
active=$((active - 1))
printf '%s\n' "$active" > "$state/active"
end=$(date +%s%N)
printf 'END\t%s\t%s\t%s\t%s\n' "$seq" "$(basename -- "$file")" "$end" "$active" >> "$state/events.tsv"
flock -u 9
exit "$status"
WRAPPER_EOF
chmod +x "$EMBED_PATH"

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import glob
import os
import re
import sqlite3
import subprocess

import pytest

SCRIPT = "/home/user/process_dataset.sh"
RAW_DIR = "/home/user/raw_data"
DB = "/home/user/dataset.db"
LOG = "/home/user/benchmark.log"
STATE = "/tmp/verifier_embed_state"


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."

    with open(SCRIPT, "r", errors="replace") as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert "bash" in first_line, "process_dataset.sh must be a Bash script."
    uncommented = "\n".join(line.split("#", 1)[0] for line in source.splitlines())
    assert re.search(r"\b(?:xargs|parallel)\b", uncommented), \
        "The script must use xargs or GNU parallel for parallel processing."
    assert re.search(r"\btime\b|\$\{?SECONDS\}?", uncommented), \
        "The script must measure its runs using time or $SECONDS."

    # Replace the original data with fresh, unpredictable inputs so precomputed
    # database contents cannot satisfy the verification run.
    os.makedirs(RAW_DIR, exist_ok=True)
    for path in glob.glob(os.path.join(RAW_DIR, "doc_*.txt")):
        os.unlink(path)
    for i in range(1, 51):
        tokens = [os.urandom(4).hex() for _ in range(7 + (i * 13) % 31)]
        with open(os.path.join(RAW_DIR, f"doc_{i}.txt"), "w") as f:
            f.write(" ".join(tokens) + "\n")

    for path in (DB, LOG):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    for name in ("events.tsv", "boundaries.tsv"):
        open(os.path.join(STATE, name), "w").close()
    with open(os.path.join(STATE, "seq"), "w") as f:
        f.write("0\n")
    with open(os.path.join(STATE, "active"), "w") as f:
        f.write("0\n")

    try:
        result = subprocess.run(
            [SCRIPT], cwd="/home/user", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
        )
    except subprocess.TimeoutExpired:
        pytest.fail("process_dataset.sh did not finish within 120 seconds.")
    assert result.returncode == 0, (
        f"process_dataset.sh exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def _read_timings():
    assert os.path.exists(LOG), f"Log file {LOG} does not exist."
    with open(LOG, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 3, f"Expected exactly 3 lines in {LOG}, found {len(lines)}."

    pattern = re.compile(r"^Concurrency ([124]): ([0-9]+(?:\.[0-9]+)?) seconds$")
    timings = {}
    for line in lines:
        match = pattern.match(line)
        assert match, f"Line '{line}' does not match the expected format 'Concurrency X: Y seconds'."
        concurrency = int(match.group(1))
        assert concurrency not in timings, f"Concurrency {concurrency} appears more than once."
        timings[concurrency] = float(match.group(2))
    assert set(timings) == {1, 2, 4}, f"Expected concurrencies 1, 2, and 4. Found: {set(timings)}"
    return timings


def test_benchmark_log():
    timings = _read_timings()

    starts = {}
    ends = {}
    with open(os.path.join(STATE, "events.tsv")) as f:
        for raw in f:
            fields = raw.rstrip("\n").split("\t")
            assert len(fields) == 5, f"Malformed embedding audit event: {raw!r}"
            kind, seq, filename, timestamp, active = fields
            seq, timestamp = int(seq), int(timestamp)
            if kind == "START":
                starts[seq] = timestamp
            elif kind == "END":
                ends[seq] = timestamp

    for group, concurrency in enumerate((1, 2, 4)):
        seqs = range(group * 50 + 1, group * 50 + 51)
        elapsed = (max(ends[s] for s in seqs) - min(starts[s] for s in seqs)) / 1e9
        reported = timings[concurrency]
        # Accommodate integer $SECONDS measurements and small setup/insert costs,
        # while requiring the logged number to be an actual measurement.
        assert max(0.0, elapsed - 1.1) <= reported <= elapsed + 3.0, (
            f"Reported time for concurrency {concurrency} ({reported}) is not "
            f"consistent with its observed processing time ({elapsed:.3f})."
        )


def test_three_complete_runs_and_parallelism():
    events = []
    with open(os.path.join(STATE, "events.tsv")) as f:
        for raw in f:
            kind, seq, filename, timestamp, active = raw.rstrip("\n").split("\t")
            events.append((kind, int(seq), filename, int(timestamp), int(active)))

    starts = [event for event in events if event[0] == "START"]
    ends = [event for event in events if event[0] == "END"]
    assert len(starts) == 150, f"Expected 150 mock_embed calls, observed {len(starts)}."
    assert len(ends) == 150, f"Expected 150 completed mock_embed calls, observed {len(ends)}."
    assert {e[1] for e in starts} == set(range(1, 151))
    assert {e[1] for e in ends} == set(range(1, 151))

    expected_files = {f"doc_{i}.txt" for i in range(1, 51)}
    expected_max = (1, 2, 4)
    for group in range(3):
        lo, hi = group * 50 + 1, group * 50 + 50
        group_starts = [e for e in starts if lo <= e[1] <= hi]
        assert {e[2] for e in group_starts} == expected_files, (
            f"Run {group + 1} did not invoke mock_embed exactly once for every input file."
        )
        maximum = max(e[4] for e in group_starts)
        assert maximum == expected_max[group], (
            f"Run {group + 1} reached {maximum} concurrent embedding jobs; "
            f"expected {expected_max[group]}."
        )

    boundaries = {}
    with open(os.path.join(STATE, "boundaries.tsv")) as f:
        for raw in f:
            seq, count, active_before = map(int, raw.rstrip("\n").split("\t"))
            boundaries[seq] = (count, active_before)
    assert set(boundaries) == {1, 51, 101}, "Could not observe the start of all three runs."
    for seq in (1, 51, 101):
        count, active_before = boundaries[seq]
        assert active_before == 0, f"A new run began before the previous run completed (call {seq})."
        assert count == 0, f"The documents table was not empty before run beginning at call {seq}."


def test_database_exists():
    assert os.path.exists(DB), f"Database {DB} does not exist."


def test_database_content():
    conn = sqlite3.connect(DB)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='documents';")
    assert cursor.fetchone() is not None, "Table 'documents' does not exist in the database."

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")
    assert {row[0] for row in cursor.fetchall()} == {"documents"}, "The database must contain only the documents table."

    cursor.execute("PRAGMA table_info(documents)")
    columns = [(row[1], row[2].upper()) for row in cursor.fetchall()]
    assert columns == [("filename", "TEXT"), ("word_count", "INTEGER"), ("embedding", "TEXT")], \
        f"Unexpected documents schema: {columns}"

    cursor.execute("SELECT count(*) FROM documents;")
    count = cursor.fetchone()[0]
    assert count == 50, f"Expected exactly 50 rows in 'documents' table, found {count}."

    cursor.execute("SELECT filename, word_count, embedding FROM documents;")
    rows = cursor.fetchall()
    conn.close()
    db_data = {row[0]: {"word_count": row[1], "embedding": row[2]} for row in rows}

    files = glob.glob(os.path.join(RAW_DIR, "doc_*.txt"))
    assert len(files) == 50, "Expected 50 raw data files."
    for file_path in files:
        filename = os.path.basename(file_path)
        assert filename in db_data, f"File {filename} is missing from the database."

        out = subprocess.check_output(["wc", "-w", file_path])
        expected_word_count = int(out.split()[0])
        out = subprocess.check_output(["wc", "-c", file_path])
        file_len = int(out.split()[0])
        expected_embedding = f"[{file_len}, 0.5, -0.1]"

        actual_word_count = db_data[filename]["word_count"]
        actual_embedding = db_data[filename]["embedding"]
        assert actual_word_count == expected_word_count, (
            f"Word count mismatch for {filename}: expected {expected_word_count}, got {actual_word_count}."
        )
        assert actual_embedding == expected_embedding, (
            f"Embedding mismatch for {filename}: expected '{expected_embedding}', got '{actual_embedding}'."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
