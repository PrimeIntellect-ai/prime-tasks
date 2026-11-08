#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

def test_migrated_logs_content():
    raw_path = "/home/user/data/raw.csv"
    migrated_path = "/home/user/data/migrated_logs.csv"

    assert os.path.isfile(migrated_path), f"File {migrated_path} is missing. Did you run migrate.sh?"

    with open(raw_path, "r") as f:
        raw_lines = f.read().splitlines()

    expected_migrated = []
    for line in raw_lines:
        if not line.strip():
            continue
        parts = line.split(",")
        expected_migrated.append(f"{parts[0]},{parts[1]},GET,{parts[2]}")

    with open(migrated_path, "r") as f:
        migrated_lines = f.read().splitlines()

    assert migrated_lines == expected_migrated, f"Content of {migrated_path} does not match expected schema migration."

def test_libvalidate_wrapper():
    lib_path = "/home/user/lib/libvalidate.sh"
    assert os.path.isfile(lib_path), f"File {lib_path} is missing."

    with open(lib_path, "r") as f:
        content = f.read()

    assert "validate_ip_v2" in content, "validate_ip_v2 function is missing in libvalidate.sh."
    assert "validate_ip" in content, "Original validate_ip function should not be removed."

def test_rate_limiter_exists():
    rl_path = "/home/user/app/rate_limiter.sh"
    assert os.path.isfile(rl_path), f"File {rl_path} is missing."
    assert os.access(rl_path, os.X_OK), f"File {rl_path} is not executable."

def test_final_processed_output():
    migrated_path = "/home/user/data/migrated_logs.csv"
    processed_path = "/home/user/output/final_processed.txt"
    errors_path = "/home/user/output/errors.log"

    assert os.path.isfile(processed_path), f"File {processed_path} is missing. Did you run processor.sh?"
    assert os.path.isfile(errors_path), f"File {errors_path} is missing."

    with open(migrated_path, "r") as f:
        migrated_lines = f.read().splitlines()

    expected_processed = []
    expected_errors = []

    import re
    ip_regex = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$")
    counts = {}

    for line in migrated_lines:
        if not line.strip():
            continue
        ts, ip, method, endpoint = line.split(",")

        if not ip_regex.match(ip):
            expected_errors.append(f"INVALID IP: {ip}")
            continue

        key = (ip, ts)
        counts[key] = counts.get(key, 0) + 1

        if counts[key] > 2:
            expected_processed.append(f"{ts} {ip} {method} {endpoint} RATELIMITED")
        else:
            expected_processed.append(f"{ts} {ip} {method} {endpoint} ACCEPTED")

    with open(processed_path, "r") as f:
        processed_lines = f.read().splitlines()

    with open(errors_path, "r") as f:
        error_lines = f.read().splitlines()

    assert processed_lines == expected_processed, f"{processed_path} content does not match expected output based on rate limiting rules."
    assert error_lines == expected_errors, f"{errors_path} content does not match expected invalid IP errors."
TEST_EOF

verify() {
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1

    test -f /home/user/app/migrate.sh || return 1
    test -f /home/user/app/rate_limiter.sh || return 1
    test -x /home/user/app/rate_limiter.sh || return 1

    cat << 'PROCESSOR_EOF' > /tmp/original_processor.sh
#!/bin/bash
source /home/user/lib/libvalidate.sh

> /home/user/output/final_processed.txt
> /home/user/output/errors.log

while IFS=',' read -r ts ip method endpoint; do
    if ! validate_ip_v2 "$ip"; then
        echo "INVALID IP: $ip" >> /home/user/output/errors.log
        continue
    fi

    if /home/user/app/rate_limiter.sh "$ip" "$ts"; then
        echo "$ts $ip $method $endpoint ACCEPTED" >> /home/user/output/final_processed.txt
    else
        echo "$ts $ip $method $endpoint RATELIMITED" >> /home/user/output/final_processed.txt
    fi
done < /home/user/data/migrated_logs.csv
PROCESSOR_EOF
    cmp -s /tmp/original_processor.sh /home/user/app/processor.sh || return 1

    timeout 10s runuser -u user -- bash -c '
        source /home/user/lib/libvalidate.sh || exit 1
        declare -F validate_ip >/dev/null || exit 1
        declare -F validate_ip_v2 >/dev/null || exit 1
        validate_ip_v2 "127.0.0.1" || exit 1
        validate_ip_v2 "not_an_ip" && exit 1
        validate_ip() {
            [[ "$#" -eq 3 && "$1" == "a b" && -z "$2" && "$3" == "*" ]]
        }
        validate_ip_v2 "a b" "" "*"
    ' || return 1

    local nonce ts1 ts2 octet ip1 ip2 status
    nonce="$(date +%s%N)$$"
    ts1="$nonce"
    ts2=$((nonce + 1))
    octet=$((($$ % 200) + 1))
    ip1="198.51.100.$octet"
    ip2="203.0.113.$octet"

    timeout 10s runuser -u user -- /home/user/app/rate_limiter.sh "$ip1" "$ts1"
    status=$?
    test "$status" -eq 0 || return 1
    timeout 10s runuser -u user -- /home/user/app/rate_limiter.sh "$ip1" "$ts1"
    status=$?
    test "$status" -eq 0 || return 1
    timeout 10s runuser -u user -- /home/user/app/rate_limiter.sh "$ip1" "$ts1"
    status=$?
    test "$status" -eq 1 || return 1
    timeout 10s runuser -u user -- /home/user/app/rate_limiter.sh "$ip1" "$ts1"
    status=$?
    test "$status" -eq 1 || return 1
    timeout 10s runuser -u user -- /home/user/app/rate_limiter.sh "$ip1" "$ts2"
    status=$?
    test "$status" -eq 0 || return 1
    timeout 10s runuser -u user -- /home/user/app/rate_limiter.sh "$ip2" "$ts1"
    status=$?
    test "$status" -eq 0 || return 1

    cat > /home/user/data/raw.csv << DYNAMIC_EOF
$ts1,$ip1,/dynamic/a,AgentOne
$ts1,$ip1,/dynamic/b,AgentTwo
$ts1,$ip1,/dynamic/c,AgentThree
$ts2,$ip1,/dynamic/d,AgentFour
$ts2,$ip1,/dynamic/e,AgentFive
$ts2,$ip1,/dynamic/f,AgentSix
$ts2,$ip1,/dynamic/g,AgentSeven
$ts1,$ip2,/dynamic/h,AgentEight
$ts1,invalid_dynamic_ip,/dynamic/bad,AgentNine
DYNAMIC_EOF
    chown user:user /home/user/data/raw.csv

    timeout 10s runuser -u user -- /bin/bash /home/user/app/migrate.sh || return 1

    TS1="$ts1" TS2="$ts2" IP1="$ip1" IP2="$ip2" python3 - << 'PY_EOF' || return 1
import os

ts1 = os.environ["TS1"]
ts2 = os.environ["TS2"]
ip1 = os.environ["IP1"]
ip2 = os.environ["IP2"]
expected = [
    f"{ts1},{ip1},GET,/dynamic/a",
    f"{ts1},{ip1},GET,/dynamic/b",
    f"{ts1},{ip1},GET,/dynamic/c",
    f"{ts2},{ip1},GET,/dynamic/d",
    f"{ts2},{ip1},GET,/dynamic/e",
    f"{ts2},{ip1},GET,/dynamic/f",
    f"{ts2},{ip1},GET,/dynamic/g",
    f"{ts1},{ip2},GET,/dynamic/h",
    f"{ts1},invalid_dynamic_ip,GET,/dynamic/bad",
]
with open("/home/user/data/migrated_logs.csv") as f:
    actual = f.read().splitlines()
assert actual == expected, (actual, expected)
PY_EOF

    timeout 10s runuser -u user -- /home/user/app/processor.sh || return 1

    TS1="$ts1" TS2="$ts2" IP1="$ip1" IP2="$ip2" python3 - << 'PY_EOF' || return 1
import os

ts1 = os.environ["TS1"]
ts2 = os.environ["TS2"]
ip1 = os.environ["IP1"]
ip2 = os.environ["IP2"]
expected_processed = [
    f"{ts1} {ip1} GET /dynamic/a ACCEPTED",
    f"{ts1} {ip1} GET /dynamic/b ACCEPTED",
    f"{ts1} {ip1} GET /dynamic/c RATELIMITED",
    f"{ts2} {ip1} GET /dynamic/d ACCEPTED",
    f"{ts2} {ip1} GET /dynamic/e ACCEPTED",
    f"{ts2} {ip1} GET /dynamic/f RATELIMITED",
    f"{ts2} {ip1} GET /dynamic/g RATELIMITED",
    f"{ts1} {ip2} GET /dynamic/h ACCEPTED",
]
with open("/home/user/output/final_processed.txt") as f:
    actual_processed = f.read().splitlines()
with open("/home/user/output/errors.log") as f:
    actual_errors = f.read().splitlines()
assert actual_processed == expected_processed, (actual_processed, expected_processed)
assert actual_errors == ["INVALID IP: invalid_dynamic_ip"], actual_errors
PY_EOF
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
