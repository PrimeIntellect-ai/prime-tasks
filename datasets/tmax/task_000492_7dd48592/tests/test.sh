#!/bin/bash
set +e
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt /tmp/cluster_sim_called /tmp/cluster_reference.json

fail_verifier() {
    echo "0" > /logs/verifier/reward.txt
    exit 0
}

# The submitted artifact must exist and compile.
[ -f /home/user/com.go ] || fail_verifier
go build -o /tmp/com_submission /home/user/com.go || fail_verifier

# Build a transparent stream monitor. It forwards the simulator's actual CSV to
# the submission while exactly accumulating the six-decimal coordinates as
# scaled integers, avoiding any assumption about the generator's pre-formatting
# arithmetic.
cat > /tmp/capture_stream.go <<'GO_EOF'
package main

import (
    "bufio"
    "bytes"
    "encoding/json"
    "fmt"
    "os"
)

type Reference struct {
    Count int64 `json:"count"`
    XSum  int64 `json:"x_sum_microunits"`
    YSum  int64 `json:"y_sum_microunits"`
    ZSum  int64 `json:"z_sum_microunits"`
}

func fixed6(b []byte) (int64, error) {
    if len(b) == 0 {
        return 0, fmt.Errorf("empty number")
    }
    sign := int64(1)
    if b[0] == '-' {
        sign = -1
        b = b[1:]
    } else if b[0] == '+' {
        b = b[1:]
    }
    if len(b) == 0 {
        return 0, fmt.Errorf("missing digits")
    }
    var whole, frac int64
    seenDot := false
    fracDigits := 0
    for _, c := range b {
        if c == '.' && !seenDot {
            seenDot = true
            continue
        }
        if c < '0' || c > '9' {
            return 0, fmt.Errorf("invalid number %q", string(b))
        }
        if !seenDot {
            whole = whole*10 + int64(c-'0')
        } else {
            if fracDigits >= 6 {
                return 0, fmt.Errorf("more than six fractional digits")
            }
            frac = frac*10 + int64(c-'0')
            fracDigits++
        }
    }
    for fracDigits < 6 {
        frac *= 10
        fracDigits++
    }
    return sign * (whole*1000000 + frac), nil
}

func main() {
    scanner := bufio.NewScanner(os.Stdin)
    scanner.Buffer(make([]byte, 4096), 1024*1024)
    out := bufio.NewWriterSize(os.Stdout, 1024*1024)
    var r Reference

    for scanner.Scan() {
        line := scanner.Bytes()
        fields := bytes.Split(line, []byte{','})
        if len(fields) != 4 {
            fmt.Fprintln(os.Stderr, "invalid simulator CSV")
            os.Exit(2)
        }
        x, err := fixed6(fields[0]); if err != nil { os.Exit(2) }
        y, err := fixed6(fields[1]); if err != nil { os.Exit(2) }
        z, err := fixed6(fields[2]); if err != nil { os.Exit(2) }
        if string(fields[3]) != "1.0" {
            fmt.Fprintln(os.Stderr, "unexpected mass")
            os.Exit(2)
        }
        r.XSum += x
        r.YSum += y
        r.ZSum += z
        r.Count++
        if _, err := out.Write(line); err != nil { os.Exit(2) }
        if err := out.WriteByte('\n'); err != nil { os.Exit(2) }
    }
    if err := scanner.Err(); err != nil { os.Exit(2) }
    if err := out.Flush(); err != nil { os.Exit(2) }

    f, err := os.Create("/tmp/cluster_reference.json")
    if err != nil { os.Exit(2) }
    if err := json.NewEncoder(f).Encode(r); err != nil { os.Exit(2) }
    if err := f.Close(); err != nil { os.Exit(2) }
}
GO_EOF
go build -o /tmp/capture_stream /tmp/capture_stream.go || fail_verifier

# Interpose only to observe the exact bytes consumed by the submission.
[ -x /app/cluster_sim ] || fail_verifier
mv /app/cluster_sim /app/cluster_sim.real || fail_verifier
restore_sim() {
    rm -f /app/cluster_sim
    if [ -e /app/cluster_sim.real ]; then
        mv /app/cluster_sim.real /app/cluster_sim
    fi
}
trap restore_sim EXIT
cat > /app/cluster_sim <<'WRAP_EOF'
#!/bin/bash
touch /tmp/cluster_sim_called
set -o pipefail
/app/cluster_sim.real "$@" | /tmp/capture_stream
WRAP_EOF
chmod 755 /app/cluster_sim

rm -f /home/user/result.json
(
    cd /home/user || exit 1
    /usr/bin/timeout 420s /tmp/com_submission
)
run_status=$?
restore_sim
trap - EXIT
[ "$run_status" -eq 0 ] || fail_verifier

cat > /tmp/test_final_state.py <<'PY_EOF'
import json
import math
import os
import re
import pytest

RESULT = "/home/user/result.json"
SOURCE = "/home/user/com.go"
REFERENCE = "/tmp/cluster_reference.json"


def test_source_artifact_and_required_implementation_features():
    assert os.path.isfile(SOURCE), f"The file {SOURCE} does not exist."
    text = open(SOURCE, "r", encoding="utf-8").read()
    # Remove comments so comments alone cannot satisfy implementation checks.
    code = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    code = re.sub(r"//.*", "", code)
    lower = code.lower()

    assert re.search(r"\bgo\s+(?:func\s*\(|[A-Za-z_][A-Za-z0-9_]*\s*\()", code), \
        "com.go must launch worker goroutines."
    assert ("chan " in code or "chan<-" in code or "<-chan" in code or
            "sync.WaitGroup" in code or "sync.waitgroup" in lower), \
        "com.go must coordinate its parallel workers."
    assert re.search(r"kahan|neumaier|compens", lower), \
        "com.go must implement an identifiable compensated summation algorithm."
    assert "1000" in code and re.search(r"\brand\.", code), \
        "com.go must perform the requested 1,000 randomized bootstrap resamples."


def test_submission_executed_the_real_stream():
    assert os.path.exists("/tmp/cluster_sim_called"), \
        "The submitted program did not execute /app/cluster_sim."
    assert os.path.isfile(REFERENCE), \
        "The submitted program did not consume the simulator stream completely."
    with open(REFERENCE) as f:
        ref = json.load(f)
    assert ref["count"] == 5_000_000, \
        f"Expected 5,000,000 streamed records, got {ref['count']}."


def test_result_json_exists():
    assert os.path.exists(RESULT), f"The file {RESULT} does not exist."
    assert os.path.isfile(RESULT), f"The path {RESULT} is not a file."


def test_result_json_format_and_metric():
    try:
        with open(RESULT, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse {RESULT} as JSON: {e}")

    assert "CoM" in data, "Key 'CoM' is missing from result.json."
    com = data["CoM"]
    for axis in ["x", "y", "z"]:
        assert axis in com, f"Key '{axis}' is missing from 'CoM' in result.json."
        assert isinstance(com[axis], (int, float)) and not isinstance(com[axis], bool), \
            f"CoM '{axis}' must be a numeric value."
        assert math.isfinite(com[axis]), f"CoM '{axis}' must be finite."

    assert "ConfidenceInterval_95" in data, \
        "Key 'ConfidenceInterval_95' is missing from result.json."
    ci = data["ConfidenceInterval_95"]
    expected_ci_keys = ["x_lower", "x_upper", "y_lower", "y_upper",
                        "z_lower", "z_upper"]
    for key in expected_ci_keys:
        assert key in ci, f"Key '{key}' is missing from 'ConfidenceInterval_95' in result.json."
        assert isinstance(ci[key], (int, float)) and not isinstance(ci[key], bool), \
            f"ConfidenceInterval_95 '{key}' must be a numeric value."
        assert math.isfinite(ci[key]), \
            f"ConfidenceInterval_95 '{key}' must be finite."

    with open(REFERENCE) as f:
        ref = json.load(f)
    denominator = ref["count"] * 1_000_000
    expected = {
        "x": ref["x_sum_microunits"] / denominator,
        "y": ref["y_sum_microunits"] / denominator,
        "z": ref["z_sum_microunits"] / denominator,
    }

    mae = max(abs(com[a] - expected[a]) for a in ("x", "y", "z"))
    threshold = 1e-10
    assert mae < threshold, (
        f"Maximum Absolute Error (MAE) threshold not met. Measured MAE: {mae}, "
        f"Threshold: {threshold}. Computed CoM: {com}. Expected CoM from the "
        f"actual emitted CSV: {expected}."
    )

    for axis in ("x", "y", "z"):
        lower = ci[f"{axis}_lower"]
        upper = ci[f"{axis}_upper"]
        assert lower < upper, f"Bootstrap interval for {axis} must be non-degenerate and ordered."
        assert lower <= com[axis] <= upper, \
            f"Bootstrap interval for {axis} does not contain the computed CoM."
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
