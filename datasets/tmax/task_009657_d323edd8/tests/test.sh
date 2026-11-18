#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier-bin
cat <<'WRAPPER_EOF' > /tmp/verifier-bin/gcc
#!/bin/bash
real_gcc=/usr/bin/gcc
saw_process=0
compile_only=0
out=""
expect_out=0
for arg in "$@"; do
    if [ "$expect_out" = 1 ]; then
        out="$arg"
        expect_out=0
        continue
    fi
    case "$arg" in
        -o) expect_out=1 ;;
        -o*) out="${arg#-o}" ;;
        -c|-S|-E) compile_only=1 ;;
        process.c|*/process.c) saw_process=1 ;;
    esac
done

"$real_gcc" "$@"
status=$?
[ "$status" -eq 0 ] || exit "$status"

if [ "$saw_process" = 1 ] && [ "$compile_only" = 0 ]; then
    [ -n "$out" ] || out="a.out"
    case "$out" in
        /*) ;;
        *) out="$PWD/$out" ;;
    esac
    if [ -f "$out" ]; then
        real_out="${out}.verifier_real"
        mv -f "$out" "$real_out"
        {
            echo '#!/bin/bash'
            echo 'touch /tmp/verifier_c_executed'
            printf 'exec %q "$@"\n' "$real_out"
        } > "$out"
        chmod +x "$out"
        touch /tmp/verifier_c_compiled
    fi
fi
exit 0
WRAPPER_EOF
chmod +x /tmp/verifier-bin/gcc
ln -sf /tmp/verifier-bin/gcc /tmp/verifier-bin/cc

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import subprocess
from decimal import Decimal

HOME = "/home/user"
PIPELINE = os.path.join(HOME, "pipeline.sh")
SOURCE = os.path.join(HOME, "process.c")
RAW = os.path.join(HOME, "raw_data.csv")
OUTPUT = os.path.join(HOME, "output.csv")
LOG = os.path.join(HOME, "pipeline.log")

FIXED_DATA = """Timestamp,CustomerName,FeedbackText,PurchaseAmount
1620000005,Charlie,Hello 世界,20.00
1620000001,Bob,👍,5.00
1620000003,Diana,Hola,10.00
1620000004,Eve,😊😊,50.00
1620000002,Alice,Great!,15.50
"""

FIXED_LINES = [
    "B***b,1,5.00",
    "A***e,6,10.25",
    "D***a,4,10.17",
    "E***e,2,25.17",
    "C***e,8,26.67",
]

DYNAMIC_DATA = """Timestamp,CustomerName,FeedbackText,PurchaseAmount
10,Quinn,नमस्ते,15.00
2,Li,é,6.00
30,Z,abc,21.00
5,Maria,नमस्ते,9.00
1,A,👍🏽,3.00
20,Omar,東京,18.00
3,Noah,é,12.00
"""


def assert_log_content():
    assert os.path.exists(LOG), "pipeline.log is missing"
    with open(LOG, "r", encoding="utf-8") as f:
        content = f.read().strip().split()
    expected_words = ["Started", "Sorted", "Processed", "Done"]
    idx = -1
    for word in expected_words:
        try:
            idx = content.index(word, idx + 1)
        except ValueError:
            raise AssertionError(
                f"Expected word '{word}' not found or not in correct order in pipeline.log"
            )


def read_output():
    assert os.path.exists(OUTPUT), "output.csv is missing"
    with open(OUTPUT, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def expected_for(raw_text):
    rows = list(csv.DictReader(raw_text.splitlines()))
    rows.sort(key=lambda row: int(row["Timestamp"]))
    amounts = []
    result = []
    for row in rows:
        name = row["CustomerName"]
        masked = name[0] + "***" + name[-1]
        count = len(row["FeedbackText"])
        amounts.append(Decimal(row["PurchaseAmount"]))
        window = amounts[max(0, len(amounts) - 3):]
        average = sum(window) / Decimal(len(window))
        result.append(f"{masked},{count},{average:.2f}")
    return result


def run_pipeline(raw_text):
    with open(RAW, "w", encoding="utf-8", newline="") as f:
        f.write(raw_text)
    for path in (OUTPUT, LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    env = os.environ.copy()
    env["PATH"] = "/tmp/verifier-bin:" + env.get("PATH", "")
    completed = subprocess.run(
        ["/bin/bash", PIPELINE],
        cwd=HOME,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"pipeline.sh failed with exit code {completed.returncode}\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def test_pipeline_script_exists():
    assert os.path.exists(PIPELINE), "pipeline.sh is missing"
    assert os.path.isfile(PIPELINE), "pipeline.sh is not a regular file"


def test_c_program_exists_and_compiles():
    assert os.path.exists(SOURCE), "process.c is missing"
    assert os.path.isfile(SOURCE), "process.c is not a regular file"
    result = subprocess.run(
        ["/usr/bin/gcc", "-std=c11", "-Wall", "-Wextra", SOURCE, "-o", "/tmp/submission_process"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"process.c does not compile:\n{result.stderr}"


def test_pipeline_processing_and_original_output():
    for marker in ("/tmp/verifier_c_compiled", "/tmp/verifier_c_executed"):
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass

    run_pipeline(FIXED_DATA)
    assert_log_content()
    lines = read_output()
    assert len(lines) == len(FIXED_LINES), (
        f"Expected {len(FIXED_LINES)} lines in output.csv, got {len(lines)}"
    )
    for i, (expected, actual) in enumerate(zip(FIXED_LINES, lines)):
        assert actual == expected, (
            f"Mismatch at line {i+1} of output.csv: expected '{expected}', got '{actual}'"
        )

    run_pipeline(DYNAMIC_DATA)
    assert_log_content()
    expected = expected_for(DYNAMIC_DATA)
    actual = read_output()
    assert actual == expected, f"Dynamic pipeline output mismatch: expected {expected}, got {actual}"

    assert os.path.exists("/tmp/verifier_c_compiled"), (
        "pipeline.sh did not compile process.c"
    )
    assert os.path.exists("/tmp/verifier_c_executed"), (
        "pipeline.sh did not execute the compiled C program"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
