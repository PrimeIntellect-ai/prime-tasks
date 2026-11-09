#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import stat
import subprocess
import tempfile
import time
import uuid

ENGINE = "/home/user/query_engine"
QUERY = os.path.join(ENGINE, "query.sh")
DB = os.path.join(ENGINE, "db.txt")
FUZZ = os.path.join(ENGINE, "fuzz.sh")
REGRESSION = os.path.join(ENGINE, "regression_test.sh")
FINAL_LOG = os.path.join(ENGINE, "final_output.log")
EXPECTED_FINAL_LINE = 'ID=3 USER="admin" OR STATUS=500 MESSAGE="Critical failure in auth module"'


def run(argv, timeout=5):
    return subprocess.run(argv, cwd=ENGINE, capture_output=True, timeout=timeout)


def test_final_output_log():
    assert os.path.isfile(FINAL_LOG), f"{FINAL_LOG} does not exist."
    with open(FINAL_LOG, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert EXPECTED_FINAL_LINE in content, f"Expected output not found in {FINAL_LOG}. Found: {content}"
    assert content == EXPECTED_FINAL_LINE, "final_output.log is not the exact stdout required by the final query"


def test_scripts_exist_and_are_executable():
    for path in (QUERY, FUZZ, REGRESSION):
        assert os.path.isfile(path), f"{path} does not exist."
        assert os.access(path, os.X_OK), f"{path} is not executable."


def test_query_sh_safe_evaluation_original_cases():
    result = run([QUERY, "test*"])
    assert result.returncode == 0, f"{QUERY} failed on safe evaluation test. Stderr: {result.stderr.decode(errors='replace')}"
    assert b"Wildcard test" in result.stdout, "query.sh did not return the expected result for special character query."

    result2 = run([QUERY, 'USER="admin"'])
    assert result2.returncode == 0, f"{QUERY} failed on quotes test."
    assert b"Login successful" in result2.stdout, "query.sh did not return expected result for quotes query."


def test_query_uses_safe_grep_E_and_handles_unpredictable_data():
    with open(QUERY, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert not re.search(r"^\s*(?:source|\.)\s+.*bad_utils", source, re.MULTILINE), "query.sh still sources the broken utility overrides"
    assert not re.search(r"(^|[;|&\s])eval([;|&\s]|$)", source), "query.sh still uses unsafe eval"
    assert re.search(r"(?:^|[\s;/])(?:command\s+)?(?:/usr/bin/|/bin/)?grep\s+[^\n]*-E|(?:^|[\s;/])(?:command\s+)?(?:/usr/bin/|/bin/)?grep\s+-E", source, re.MULTILINE), "query.sh must search with grep -E"

    original_db = open(DB, "rb").read()
    token = "TOKEN_" + uuid.uuid4().hex
    rows = [
        f'ID=71 USER="alpha_{token}" STATUS=200 MESSAGE="first {token}"',
        f'ID=72 USER="beta" STATUS=503 MESSAGE="second_{token} test*"',
        f'ID=73 USER="gamma" STATUS=404 MESSAGE="brackets[{token}]"',
        f'ID=74 USER="delta" STATUS=500 MESSAGE="plain"',
    ]
    try:
        with open(DB, "w", encoding="utf-8") as f:
            f.write("\n".join(rows) + "\n")

        patterns = [
            token,
            f'USER="alpha_{token}"',
            "STATUS=(200|503)",
            r"test\*",
            "^ID=7[34] ",
            f"first {token}|second_{token}",
            "",
        ]
        started = time.monotonic()
        for pattern in patterns:
            expected = subprocess.run(["/bin/grep", "-E", "--", pattern, DB], capture_output=True)
            actual = run([QUERY, pattern], timeout=2)
            assert actual.returncode == expected.returncode, f"wrong exit status for pattern {pattern!r}: {actual.stderr.decode(errors='replace')}"
            assert actual.stdout == expected.stdout, f"wrong query output for unpredictable pattern {pattern!r}"
            assert actual.stderr == expected.stderr, f"unexpected diagnostics for pattern {pattern!r}"
        assert time.monotonic() - started < 1.5, "query.sh is still delayed by the broken local grep override"

        marker1 = os.path.join(tempfile.gettempdir(), "query_injection_" + uuid.uuid4().hex)
        marker2 = os.path.join(tempfile.gettempdir(), "query_substitution_" + uuid.uuid4().hex)
        injection_inputs = [f'.*; touch {marker1}', f'$(touch {marker2}).*']
        for value in injection_inputs:
            try:
                run([QUERY, value], timeout=2)
            except subprocess.TimeoutExpired:
                raise AssertionError(f"query.sh hung on unsafe input {value!r}")
        assert not os.path.exists(marker1), "query input was evaluated as a shell command"
        assert not os.path.exists(marker2), "command substitution in query input was executed"
    finally:
        with open(DB, "wb") as f:
            f.write(original_db)


def test_regression_suite_exercises_query_and_detects_failure():
    saved = tempfile.mktemp(prefix="saved_query_", dir="/tmp")
    log = tempfile.mktemp(prefix="regression_args_", dir="/tmp")
    os.rename(QUERY, saved)
    try:
        wrapper = f'''#!/bin/bash
printf '%s:%s\\n' "${{#1}}" "$1" >> {shlex.quote(log)}
exec {shlex.quote(saved)} "$@"
'''
        with open(QUERY, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(QUERY, 0o755)

        result = run([REGRESSION], timeout=15)
        assert result.returncode == 0, f"{REGRESSION} failed with exit code {result.returncode}. Stderr: {result.stderr.decode(errors='replace')}"
        assert os.path.isfile(log), "regression_test.sh never invoked query.sh"
        calls = open(log, "r", encoding="utf-8", errors="replace").read().splitlines()
        values = [line.split(":", 1)[1] for line in calls if ":" in line]
        assert "" in values, "regression_test.sh does not test an empty query"
        assert any(v and not any(c in v for c in '*[\"\'\\?') for v in values), "regression_test.sh does not test a normal query"
        assert any(any(c in v for c in '*[\"\'\\?') for v in values), "regression_test.sh does not test a special-character query"
        assert len(set(values)) >= 3, "regression_test.sh must exercise at least three distinct cases"

        with open(QUERY, "w", encoding="utf-8") as f:
            f.write("#!/bin/bash\n# Deliberately wrong engine used to check the tests.\nexit 0\n")
        os.chmod(QUERY, 0o755)
        bad_result = run([REGRESSION], timeout=15)
        assert bad_result.returncode == 1, "regression_test.sh does not return 1 when query.sh produces incorrect results"
    finally:
        if os.path.exists(QUERY):
            os.unlink(QUERY)
        os.rename(saved, QUERY)
        if os.path.exists(log):
            os.unlink(log)


def test_fuzzer_generates_and_feeds_varied_special_inputs():
    saved = tempfile.mktemp(prefix="saved_query_", dir="/tmp")
    log = tempfile.mktemp(prefix="fuzz_args_", dir="/tmp")
    os.rename(QUERY, saved)
    try:
        wrapper = f'''#!/bin/bash
printf '%s\\0' "$1" >> {shlex.quote(log)}
exit 0
'''
        with open(QUERY, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(QUERY, 0o755)

        try:
            result = run([FUZZ], timeout=20)
        except subprocess.TimeoutExpired:
            raise AssertionError("fuzz.sh did not terminate in a reasonable time")
        assert result.returncode == 0, f"fuzz.sh failed: {result.stderr.decode(errors='replace')}"
        assert os.path.isfile(log), "fuzz.sh never invoked query.sh"
        raw = open(log, "rb").read()
        calls = [x.decode("utf-8", errors="replace") for x in raw.split(b"\0") if x != b""]
        assert len(calls) >= 10, "fuzz.sh generated too few test inputs"
        assert len(set(calls)) >= 8, "fuzz.sh inputs are not sufficiently varied/random"
        combined = "".join(calls)
        assert any(c.isalnum() for c in combined), "fuzz.sh does not generate alphanumeric characters"
        for special in ['*', '[', '"', "'", '\\', '?']:
            assert special in combined, f"fuzz.sh did not generate required special character {special!r}"
    finally:
        if os.path.exists(QUERY):
            os.unlink(QUERY)
        os.rename(saved, QUERY)
        if os.path.exists(log):
            os.unlink(log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
