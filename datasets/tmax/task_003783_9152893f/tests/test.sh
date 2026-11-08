#!/bin/bash
set -u
mkdir -p /logs/verifier

verify() {
    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re


def test_result_txt_exists_and_correct():
    path = "/home/user/result.txt"
    assert os.path.isfile(path), f"{path} is missing. Did you run your main.go program and save the output?"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "99.99450", f"Expected result.txt to exactly contain '99.99450', found '{content}'"


def test_fuzz_test_exists():
    path = "/home/user/uptime-app/calc_test.go"
    assert os.path.isfile(path), f"{path} is missing. You need to create the fuzz test file."
    with open(path, "r") as f:
        content = f.read()
    assert "func FuzzParseMetric(f *testing.F)" in content, "calc_test.go is missing the fuzzer function signature: func FuzzParseMetric(f *testing.F)"
    assert re.search(r"\bf\s*\.\s*Fuzz\s*\(", content), "FuzzParseMetric must register a fuzz function with f.Fuzz"
    assert re.search(r"\bParseMetric\s*\(", content), "The fuzz test must exercise ParseMetric"


def test_calculate_average_signature():
    path = "/home/user/uptime-app/calc.go"
    assert os.path.isfile(path), f"{path} is missing"
    with open(path, "r") as f:
        content = f.read()
    match = re.search(r"func\s+CalculateAverage\s*\([^)]*\[\]float32\)\s+float64", content)
    assert match is not None, "CalculateAverage signature in calc.go is not updated to return float64"


def test_main_go_exists():
    path = "/home/user/uptime-app/main.go"
    assert os.path.isfile(path), f"{path} is missing. You need to write the main application logic here."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    app=/home/user/uptime-app
    pkg=$(sed -nE 's/^[[:space:]]*package[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/p' "$app/calc.go" | head -n1)
    [[ "$pkg" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1

    cat > "$app/verifier_behavior_test.go" <<EOF
package $pkg

import (
    "math"
    "testing"
)

func TestVerifierParseMetricVariations(t *testing.T) {
    cases := []string{
        "99.5",
        "99.5%",
        "  99.5 %",
        "99.5%  ",
        "\t99.5%\r\n",
        "  % 99.5 %  ",
    }
    for _, input := range cases {
        got, err := ParseMetric(input)
        if err != nil {
            t.Fatalf("ParseMetric(%q) returned an error: %v", input, err)
        }
        if math.Abs(float64(got)-99.5) > 0.00001 {
            t.Fatalf("ParseMetric(%q) = %v, want 99.5", input, got)
        }
    }
}

func TestVerifierParseMetricInvalidDoesNotSucceed(t *testing.T) {
    if _, err := ParseMetric("not-a-metric"); err == nil {
        t.Fatal("ParseMetric accepted a nonnumeric metric")
    }
}

func TestVerifierCalculateAverageUsesFloat64Accumulation(t *testing.T) {
    metrics := make([]float32, 100001)
    metrics[0] = 100000000
    for i := 1; i < len(metrics); i++ {
        metrics[i] = 1
    }
    var sum float64
    for _, metric := range metrics {
        sum += float64(metric)
    }
    want := sum / float64(len(metrics))
    if got := CalculateAverage(metrics); got != want {
        t.Fatalf("CalculateAverage returned %.17g, want %.17g", got, want)
    }
    if got := CalculateAverage(nil); got != 0 {
        t.Fatalf("CalculateAverage(nil) = %v, want 0", got)
    }
}
EOF
    trap 'rm -f /home/user/uptime-app/verifier_behavior_test.go; if [ -n "${backup:-}" ] && [ -f "$backup" ]; then cp "$backup" /home/user/uptime-app/logs/raw_metrics.txt; fi' RETURN

    (cd "$app" && go test ./...) || return 1
    (cd "$app" && go test -run '^$' -fuzz '^FuzzParseMetric$' -fuzztime=1s -parallel=1) || return 1

    backup=$(mktemp)
    cp "$app/logs/raw_metrics.txt" "$backup" || return 1

    check_result() {
        python3 - "$1" /home/user/result.txt <<'PY'
import os
import struct
import sys

raw_path, result_path = sys.argv[1:]
assert os.path.isfile(result_path), "main program did not create /home/user/result.txt"
values = []
with open(raw_path, "r", newline="") as stream:
    for line in stream:
        cleaned = line.strip()
        while cleaned.startswith("%") or cleaned.endswith("%"):
            cleaned = cleaned.strip("%").strip()
        value = float(cleaned)
        values.append(struct.unpack("f", struct.pack("f", value))[0])
assert values, "verification input unexpectedly contained no metrics"
total = 0.0
for value in values:
    total += value
expected = format(total / len(values), ".5f")
with open(result_path, "r") as stream:
    actual = stream.read().strip()
assert actual == expected, f"main program wrote {actual!r}; expected {expected!r} from the supplied metrics"
PY
    }

    rm -f /home/user/result.txt
    (cd "$app" && go run .) || return 1
    check_result "$app/logs/raw_metrics.txt" || return 1

    python3 - "$app/logs/raw_metrics.txt" <<'PY'
import random
import sys

rng = random.SystemRandom()
formats = ["  {v}%\n", "{v}%  \n", "\t{v}%\r\n", " {v} % \n", "{v}\n"]
with open(sys.argv[1], "w", newline="") as stream:
    for i in range(37):
        value = f"{rng.uniform(1.0, 98.0):.6f}"
        stream.write(formats[i % len(formats)].format(v=value))
PY
    rm -f /home/user/result.txt
    (cd "$app" && go run .) || return 1
    check_result "$app/logs/raw_metrics.txt" || return 1

    cp "$backup" "$app/logs/raw_metrics.txt" || return 1
    rm -f /home/user/result.txt
    (cd "$app" && go run .) || return 1
    check_result "$app/logs/raw_metrics.txt" || return 1
    [[ "$(tr -d '\r\n' < /home/user/result.txt)" == "99.99450" ]] || return 1

    rm -f "$app/verifier_behavior_test.go" "$backup"
    trap - RETURN
    return 0
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
