#!/bin/bash
set -u
mkdir -p /logs/verifier

if (
    set -e
    PIPELINE_DIR=/home/user/pipeline

    test -f "$PIPELINE_DIR/requirements.txt"
    test -f "$PIPELINE_DIR/transform.py"
    test -f "$PIPELINE_DIR/build.sh"
    test -x "$PIPELINE_DIR/build.sh"
    test -f "$PIPELINE_DIR/input.csv"
    test -f "$PIPELINE_DIR/expected.csv"

    workdir=$(mktemp -d)
    cp "$PIPELINE_DIR/input.csv" "$workdir/input.original.csv"
    cp "$PIPELINE_DIR/expected.csv" "$workdir/expected.original.csv"
    cp "$PIPELINE_DIR/transform.py" "$workdir/transform.original.py"

    cleanup() {
        cp "$workdir/input.original.csv" "$PIPELINE_DIR/input.csv"
        cp "$workdir/expected.original.csv" "$PIPELINE_DIR/expected.csv"
        cp "$workdir/transform.original.py" "$PIPELINE_DIR/transform.py"
        rm -rf "$workdir"
    }
    trap cleanup EXIT

    # Independently verify that the repaired dependency lock resolves in a clean environment.
    python3 -m venv "$workdir/requirements-venv"
    timeout 600 "$workdir/requirements-venv/bin/pip" install -q -r "$PIPELINE_DIR/requirements.txt"
    "$workdir/requirements-venv/bin/pip" check

    # Execute the real pipeline from a clean artifact state.
    cd "$PIPELINE_DIR"
    rm -rf venv output.csv final_score.txt
    timeout 600 ./build.sh

    # Preserve the original verifier's assertions.
    python3 - <<'PY'
import os

pipeline = "/home/user/pipeline"
final_score_path = os.path.join(pipeline, "final_score.txt")
assert os.path.isfile(final_score_path), f"File {final_score_path} does not exist. Did the pipeline finish?"
with open(final_score_path) as f:
    content = f.read().strip()
assert content == "105.2432", f"Expected final_score.txt to contain '105.2432', but got '{content}'."

output_path = os.path.join(pipeline, "output.csv")
expected_path = os.path.join(pipeline, "expected.csv")
assert os.path.isfile(output_path), f"File {output_path} does not exist. Did transform.py run successfully?"
assert os.path.isfile(expected_path), f"File {expected_path} is missing. Do not delete the truth data."
with open(output_path) as f:
    output = f.read().strip()
with open(expected_path) as f:
    expected = f.read().strip()
assert output == expected, "The content of output.csv does not exactly match expected.csv."
PY

    # Exercise transform.py independently on unseen data, without an expected.csv
    # available for it to copy.
    transform_test="$workdir/transform-test"
    mkdir "$transform_test"
    cp "$workdir/transform.original.py" "$transform_test/transform.py"
    cat > "$transform_test/input.csv" <<'EOF'
ID,Value
7,1.2
8,4.4
9,10.0
EOF
    python3 - "$transform_test/input.csv" "$transform_test/wanted.csv" <<'PY'
import csv
import sys
from decimal import Decimal

source, destination = sys.argv[1:]
with open(source, newline="") as src, open(destination, "w", newline="") as dst:
    reader = csv.DictReader(src)
    writer = csv.writer(dst, lineterminator="\n")
    writer.writerow(["ID", "Value"])
    for row in reader:
        value = Decimal(row["Value"]) * Decimal("2.5")
        writer.writerow([row["ID"], f"{value:.1f}"])
PY
    (
        cd "$transform_test"
        "$workdir/requirements-venv/bin/python" transform.py
    )
    cmp "$transform_test/output.csv" "$transform_test/wanted.csv"

    # Run build.sh on alternate derived data. Wrap transform.py with a marker so
    # the test also proves that build.sh actually invokes the transformation.
    cp "$transform_test/input.csv" "$PIPELINE_DIR/input.csv"
    cp "$transform_test/wanted.csv" "$PIPELINE_DIR/expected.csv"
    export VERIFY_ORIGINAL_TRANSFORM="$workdir/transform.original.py"
    export VERIFY_TRANSFORM_MARKER="$workdir/transform-ran"
    cat > "$PIPELINE_DIR/transform.py" <<'PY'
import os
import runpy

with open(os.environ["VERIFY_TRANSFORM_MARKER"], "w") as marker:
    marker.write("ran\n")
runpy.run_path(os.environ["VERIFY_ORIGINAL_TRANSFORM"], run_name="__main__")
PY

    rm -f output.csv final_score.txt "$VERIFY_TRANSFORM_MARKER"
    timeout 600 ./build.sh
    test -f "$VERIFY_TRANSFORM_MARKER"
    cmp output.csv expected.csv

    count=$(tail -n +2 expected.csv | wc -l)
    sum=$(awk -F, 'NR > 1 { total += $2 } END { print total }' expected.csv)
    wanted_score=$(printf 'scale=4; %s / %s * 3.14159\n' "$sum" "$count" | bc)
    actual_score=$(tr -d '[:space:]' < final_score.txt)
    test "$actual_score" = "$wanted_score"
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
