#!/bin/bash
mkdir -p /logs/verifier
ok=1
SCRIPT_PATH=/home/user/fit_models.sh
RESULTS_PATH=/home/user/regression_results.csv

# Add structural checks for the required Bash implementation and parallelism.
if [ ! -f "$SCRIPT_PATH" ] || [ ! -x "$SCRIPT_PATH" ]; then
    ok=0
else
    if ! head -n 1 "$SCRIPT_PATH" | grep -Eq '^#!.*bash([[:space:]]|$)'; then
        ok=0
    fi

    # Ignore comment-only lines and trailing comments for these source checks.
    SCRIPT_CODE="$(grep -v '^[[:space:]]*#' "$SCRIPT_PATH" | sed 's/[[:space:]]#.*$//')"

    # Reject prohibited high-level language invocations.
    if printf '%s\n' "$SCRIPT_CODE" | grep -Eiq '(^|[^[:alnum:]_])(python([0-9.]*)?|pypy([0-9.]*)?|perl|ruby|node(js)?|Rscript|php|lua|julia)([^[:alnum:]_]|$)'; then
        ok=0
    fi
    if printf '%s\n' "$SCRIPT_CODE" | grep -Eiq '(^|[;&|()[:space:]])(command[[:space:]]+|exec[[:space:]]+|env[[:space:]]+)?([^;&|()[:space:]]*/)?R([;&|()[:space:]]|$)'; then
        ok=0
    fi

    # Require either xargs -P or a background-job plus wait implementation.
    if ! printf '%s\n' "$SCRIPT_CODE" | grep -Eq '(^|[[:space:]])xargs([[:space:]][^#;&|]*)?[[:space:]]-P([[:space:]]*[0-9]+)?'; then
        if ! { printf '%s\n' "$SCRIPT_CODE" | grep -Eq '(^|[[:space:];])&([[:space:];]|$)' &&
               printf '%s\n' "$SCRIPT_CODE" | grep -Eq '(^|[[:space:];])wait([[:space:];]|$)'; }; then
            ok=0
        fi
    fi
fi

# Run the submitted artifact on the original inputs before retaining the original assertions.
rm -f "$RESULTS_PATH"
if [ -f "$SCRIPT_PATH" ] && [ -x "$SCRIPT_PATH" ]; then
    if ! timeout 20s su -s /bin/bash user -c 'cd /home/user && ./fit_models.sh'; then
        ok=0
    fi
else
    ok=0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

SCRIPT_PATH = "/home/user/fit_models.sh"
RESULTS_PATH = "/home/user/regression_results.csv"

EXPECTED_RESULTS = [
    "Jupiter,3.00,2.00",
    "Mars,10.00,0.00",
    "Saturn,10.00,-60.00",
    "Venus,-10.00,110.00"
]

def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

def test_results_file_exists():
    assert os.path.isfile(RESULTS_PATH), f"Results file {RESULTS_PATH} is missing."

def test_results_content():
    with open(RESULTS_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(EXPECTED_RESULTS), f"Expected {len(EXPECTED_RESULTS)} lines in {RESULTS_PATH}, found {len(lines)}."

    for i, expected_line in enumerate(EXPECTED_RESULTS):
        assert lines[i] == expected_line, f"Line {i+1} mismatch. Expected '{expected_line}', got '{lines[i]}'."
TEST_EOF

if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    ok=0
fi

# Replace the inputs with unpredictable planets and coefficients, then derive the oracle.
TMPROOT="$(mktemp -d)"
BACKUP="$TMPROOT/raw_data"
ORIGINAL_RESULTS="$TMPROOT/original_results.csv"
cp "$RESULTS_PATH" "$ORIGINAL_RESULTS" 2>/dev/null || true

if mv /home/user/raw_data "$BACKUP"; then
    mkdir -p /home/user/raw_data

    make_planet() {
        p="$1"
        m="$2"
        c="$3"
        file="/home/user/raw_data/$p.txt"
        : > "$file"
        for x in 2 5 9 14; do
            y=$((m * x + c))
            printf '%s|%d|%d,%d,%d\n' "$p" "$x" "$((y - 3))" "$y" "$((y + 3))" >> "$file"
        done
    }

    P1="Astra${RANDOM}${RANDOM}"
    P2="Nebula${RANDOM}${RANDOM}"
    P3="Zephyr${RANDOM}${RANDOM}"
    make_planet "$P1" "$((RANDOM % 8 + 2))" "$((RANDOM % 31 - 15))"
    make_planet "$P2" "$((-(RANDOM % 8 + 2)))" "$((RANDOM % 31 - 15))"
    make_planet "$P3" "$((RANDOM % 11 + 1))" "$((RANDOM % 41 - 20))"
    chown -R user:user /home/user/raw_data
    chmod -R u+rwX /home/user/raw_data

    awk -F'[|,]' '
        {
            p=$1; x=$2+0; y=($3+$4+$5)/3
            n[p]++; sx[p]+=x; sy[p]+=y; sxy[p]+=x*y; sx2[p]+=x*x
        }
        END {
            for (p in n) {
                d=n[p]*sx2[p]-sx[p]*sx[p]
                m=(n[p]*sxy[p]-sx[p]*sy[p])/d
                c=(sy[p]-m*sx[p])/n[p]
                printf "%s,%.2f,%.2f\n", p, m, c
            }
        }
    ' /home/user/raw_data/*.txt | LC_ALL=C sort > "$TMPROOT/expected.csv"

    rm -f "$RESULTS_PATH"
    if ! timeout 20s su -s /bin/bash user -c 'cd /home/user && ./fit_models.sh'; then
        ok=0
    elif [ ! -f "$RESULTS_PATH" ] || ! cmp -s "$TMPROOT/expected.csv" "$RESULTS_PATH"; then
        ok=0
    fi

    rm -rf /home/user/raw_data
    mv "$BACKUP" /home/user/raw_data
    if [ -f "$ORIGINAL_RESULTS" ]; then
        cp "$ORIGINAL_RESULTS" "$RESULTS_PATH"
        chown user:user "$RESULTS_PATH" 2>/dev/null || true
    fi
else
    ok=0
fi
rm -rf "$TMPROOT"

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
