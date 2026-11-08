#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shlex
import stat
import string
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/rate_limit.sh"
TEST_SCRIPT_PATH = "/home/user/test_limiter.py"


def run_script(input_data):
    return subprocess.run(
        [SCRIPT_PATH],
        input=input_data,
        capture_output=True,
        text=True,
        timeout=10,
    )


def expected_for(lines):
    counts = {}
    output = []
    for line in lines:
        timestamp, ip_address, request_path = line.split()
        if not request_path.startswith("/api/"):
            output.append(f"INVALID {ip_address} {request_path}")
            continue
        key = (timestamp, ip_address)
        counts[key] = counts.get(key, 0) + 1
        action = "ALLOW" if counts[key] <= 2 else "DENY"
        output.append(f"{action} {ip_address} {request_path}")
    return "\n".join(output) + "\n"


def test_files_exist():
    """Verify that both required files exist."""
    assert os.path.isfile(SCRIPT_PATH), f"Missing script: {SCRIPT_PATH}"
    assert os.path.isfile(TEST_SCRIPT_PATH), f"Missing test script: {TEST_SCRIPT_PATH}"


def test_script_is_executable():
    """Verify that the shell script is executable."""
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_python_test_script_passes():
    """Verify that the student's test script runs successfully and exits with 0."""
    result = subprocess.run(
        ["python3", TEST_SCRIPT_PATH],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Student test script failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )


def test_rate_limit_logic():
    """Verify the logic of rate_limit.sh using the original hidden test set."""
    input_data = (
        "1620000000 192.168.1.1 /api/v1/users\n"
        "1620000000 192.168.1.1 /api/v1/data\n"
        "1620000000 192.168.1.1 /api/v1/settings\n"
        "1620000000 10.0.0.5 /about\n"
        "1620000001 192.168.1.1 /api/v1/users\n"
        "1620000001 192.168.1.1 /api/v1/users\n"
        "1620000001 192.168.1.1 /api/v1/users\n"
        "1620000001 10.0.0.5 /api/v1/test\n"
        "1620000001 10.0.0.5 /api/v1/test2\n"
        "1620000001 10.0.0.5 /api/v1/test3\n"
        "1620000002 10.0.0.5 /API/test\n"
        "1620000002 10.0.0.5 api/test\n"
    )

    expected_output = (
        "ALLOW 192.168.1.1 /api/v1/users\n"
        "ALLOW 192.168.1.1 /api/v1/data\n"
        "DENY 192.168.1.1 /api/v1/settings\n"
        "INVALID 10.0.0.5 /about\n"
        "ALLOW 192.168.1.1 /api/v1/users\n"
        "ALLOW 192.168.1.1 /api/v1/users\n"
        "DENY 192.168.1.1 /api/v1/users\n"
        "ALLOW 10.0.0.5 /api/v1/test\n"
        "ALLOW 10.0.0.5 /api/v1/test2\n"
        "DENY 10.0.0.5 /api/v1/test3\n"
        "INVALID 10.0.0.5 /API/test\n"
        "INVALID 10.0.0.5 api/test\n"
    )

    result = run_script(input_data)
    assert result.returncode == 0, f"Script failed with exit code {result.returncode}."

    actual_output = result.stdout.strip()
    expected_output = expected_output.strip()
    assert actual_output == expected_output, (
        f"Script output did not match expected.\n"
        f"Expected:\n{expected_output}\n\nGot:\n{actual_output}"
    )


def test_rate_limit_logic_randomized():
    """Exercise unpredictable IPs, timestamps, paths, ordering, and independent keys."""
    rng = random.SystemRandom()

    def token(length=12):
        return "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(length))

    for _ in range(6):
        base = rng.randrange(1700000000, 2100000000)
        ip1 = f"10.{rng.randrange(1,255)}.{rng.randrange(1,255)}.{rng.randrange(1,255)}"
        ip2 = f"172.{rng.randrange(16,32)}.{rng.randrange(1,255)}.{rng.randrange(1,255)}"
        lines = [
            f"{base} {ip1} /api/{token()}",
            f"{base} {ip2} /api/{token()}",
            f"{base} {ip1} /api/{token()}",
            f"{base} {ip1} /{token()}",
            f"{base} {ip1} /api/{token()}",
            f"{base} {ip2} /api/{token()}",
            f"{base} {ip2} /API/{token()}",
            f"{base} {ip2} /api/{token()}",
            f"{base + 1} {ip1} /api/{token()}",
            f"{base + 1} {ip1} api/{token()}",
            f"{base + 1} {ip1} /api/{token()}",
            f"{base + 1} {ip1} /api/{token()}",
        ]
        input_data = "\n".join(lines) + "\n"
        result = run_script(input_data)
        assert result.returncode == 0, (
            f"Script failed randomized input with code {result.returncode}: {result.stderr}"
        )
        assert result.stdout == expected_for(lines), (
            f"Randomized output mismatch.\nInput:\n{input_data}\n"
            f"Expected:\n{expected_for(lines)}\nGot:\n{result.stdout}"
        )


def test_student_suite_exercises_and_asserts_required_cases():
    """Use an instrumented implementation and targeted mutants to validate the suite itself."""
    original = open(SCRIPT_PATH, "rb").read()
    original_mode = stat.S_IMODE(os.stat(SCRIPT_PATH).st_mode)
    log_fd, log_path = tempfile.mkstemp(prefix="limiter_fixture_", text=True)
    os.close(log_fd)

    oracle = f'''#!/bin/bash
set -e
tmp=$(mktemp)
cat > "$tmp"
printf '%s\\n' '__RUN__' >> {shlex.quote(log_path)}
cat "$tmp" >> {shlex.quote(log_path)}
awk '{{
  ts=$1; ip=$2; path=$3
  if (index(path, "/api/") != 1) print "INVALID " ip " " path
  else {{ key=ts SUBSEP ip; count[key]++; if (count[key] <= 2) print "ALLOW " ip " " path; else print "DENY " ip " " path }}
}}' "$tmp"
rm -f "$tmp"
'''

    mutants = [
        '''#!/bin/bash
awk '{ if (index($3,"/api/")==1) print "DENY " $2 " " $3; else print "INVALID " $2 " " $3 }'
''',
        '''#!/bin/bash
awk '{ if (index($3,"/api/")==1) print "ALLOW " $2 " " $3; else print "INVALID " $2 " " $3 }'
''',
        '''#!/bin/bash
awk '{ ts=$1; ip=$2; path=$3; if (index(path,"/api/")!=1) print "ALLOW " ip " " path; else { k=ts SUBSEP ip; c[k]++; if(c[k]<=2) print "ALLOW " ip " " path; else print "DENY " ip " " path } }'
''',
    ]

    def install(contents):
        with open(SCRIPT_PATH, "w") as f:
            f.write(contents)
        os.chmod(SCRIPT_PATH, 0o755)

    def run_student_suite():
        return subprocess.run(
            ["python3", TEST_SCRIPT_PATH],
            capture_output=True,
            text=True,
            timeout=20,
        )

    try:
        install(oracle)
        result = run_student_suite()
        assert result.returncode == 0, (
            "Student suite did not pass against a correct instrumented implementation.\n"
            f"Stdout: {result.stdout}\nStderr: {result.stderr}"
        )

        with open(log_path) as f:
            recorded = f.read().splitlines()
        runs = []
        current = None
        for line in recorded:
            if line == "__RUN__":
                current = []
                runs.append(current)
            elif current is not None and line.strip():
                current.append(line)

        assert runs, "Student suite never executed /home/user/rate_limit.sh via subprocess."
        saw_valid = False
        saw_invalid = False
        saw_excess = False
        for run in runs:
            counts = {}
            for line in run:
                parts = line.split()
                assert len(parts) == 3, f"Malformed mock input generated by student suite: {line!r}"
                ts, ip, path = parts
                if path.startswith("/api/"):
                    saw_valid = True
                    key = (ts, ip)
                    counts[key] = counts.get(key, 0) + 1
                    if counts[key] > 2:
                        saw_excess = True
                else:
                    saw_invalid = True
        assert saw_valid, "Student suite does not generate valid /api/ requests."
        assert saw_excess, "Student suite does not generate more than two valid requests per IP/second."
        assert saw_invalid, "Student suite does not generate invalid request paths."

        for index, mutant in enumerate(mutants, 1):
            install(mutant)
            result = run_student_suite()
            assert result.returncode != 0, (
                f"Student suite accepted incorrect implementation mutant {index}; "
                "it must assert ALLOW, DENY, and INVALID behavior."
            )
    finally:
        with open(SCRIPT_PATH, "wb") as f:
            f.write(original)
        os.chmod(SCRIPT_PATH, original_mode)
        try:
            os.unlink(log_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
