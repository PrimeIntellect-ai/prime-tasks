#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess

API_PROJECT_DIR = "/home/user/api_project"
ROUTER_EXEC_PATH = os.path.join(API_PROJECT_DIR, "router")
RUN_TESTS_SH_PATH = os.path.join(API_PROJECT_DIR, "run_tests.sh")
URLS_PATH = os.path.join(API_PROJECT_DIR, "urls.txt")
TEST_REPORT_PATH = os.path.join(API_PROJECT_DIR, "test_report.log")

EXPECTED_REPORT = """SUCCESS - /api/v1/health -> Route: /api/v1/health Params: NONE
SUCCESS - /api/v2/users?active=true&sort=desc -> Route: /api/v2/users Params: active=true&sort=desc
FAILURE - malformed/url/path -> INVALID_ROUTE
SUCCESS - /webhooks/stripe?sig=xyz123 -> Route: /webhooks/stripe Params: sig=xyz123
FAILURE - admin/dashboard -> INVALID_ROUTE
SUCCESS - / -> Route: / Params: NONE
"""


def report_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f.read().strip().split("\n")]


def assert_report_matches(expected_report):
    assert os.path.isfile(TEST_REPORT_PATH), f"Report file {TEST_REPORT_PATH} does not exist."
    actual_lines = report_lines(TEST_REPORT_PATH)
    expected_lines = [line.strip() for line in expected_report.strip().split("\n")]
    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in test_report.log, found {len(actual_lines)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Mismatch on line {i+1} of test_report.log.\nExpected: {expected}\nGot: {actual}"
        )


def test_router_executable_exists():
    assert os.path.isfile(ROUTER_EXEC_PATH), f"Executable {ROUTER_EXEC_PATH} was not built."
    assert os.access(ROUTER_EXEC_PATH, os.X_OK), f"{ROUTER_EXEC_PATH} is not executable."


def test_run_tests_sh_exists_and_executable():
    assert os.path.isfile(RUN_TESTS_SH_PATH), f"Script {RUN_TESTS_SH_PATH} does not exist."
    st = os.stat(RUN_TESTS_SH_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {RUN_TESTS_SH_PATH} is not executable."


def test_test_report_log_matches():
    assert_report_matches(EXPECTED_REPORT)


def test_make_rebuilds_and_router_runs():
    if os.path.lexists(ROUTER_EXEC_PATH):
        os.remove(ROUTER_EXEC_PATH)

    result = subprocess.run(
        ["make"], cwd=API_PROJECT_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, f"make failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(ROUTER_EXEC_PATH), "make did not create router"
    assert os.access(ROUTER_EXEC_PATH, os.X_OK), "make did not create an executable router"
    with open(ROUTER_EXEC_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "router is not a compiled executable"

    token = secrets.token_hex(8)
    valid = f"/verify/{token}?first=one&second={token}"
    result = subprocess.run(
        [ROUTER_EXEC_PATH, valid], cwd=API_PROJECT_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0
    assert result.stdout == f"Route: /verify/{token}\nParams: first=one&second={token}\n"

    invalid = f"invalid-{token}/route"
    result = subprocess.run(
        [ROUTER_EXEC_PATH, invalid], cwd=API_PROJECT_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode != 0


def test_run_tests_reads_urls_invokes_router_and_captures_results():
    token = secrets.token_hex(12)
    urls = [
        f"/generated/{token}",
        f"/generated/{token}/item?alpha={token}&beta=two",
        f"broken-{token}/path",
        f"/?q={token}",
    ]
    marker_route = f"/probe/{token}"
    marker_params = f"captured={token}"
    expected_lines = [
        f"SUCCESS - {urls[0]} -> Route: {marker_route} Params: {marker_params}",
        f"SUCCESS - {urls[1]} -> Route: {marker_route} Params: {marker_params}",
        f"FAILURE - {urls[2]} -> INVALID_ROUTE",
        f"SUCCESS - {urls[3]} -> Route: {marker_route} Params: {marker_params}",
    ]

    with open(URLS_PATH, "rb") as f:
        original_urls = f.read()

    real_router = os.path.join(API_PROJECT_DIR, f".router.real.{token}")
    call_log = os.path.join(API_PROJECT_DIR, f".router.calls.{token}")
    os.replace(ROUTER_EXEC_PATH, real_router)
    wrapper = f'''#!/bin/bash
printf '%s\\n' "$1" >> "{call_log}"
"{real_router}" "$@" >/dev/null 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    printf 'Route: {marker_route}\\nParams: {marker_params}\\n'
fi
exit "$status"
'''
    with open(ROUTER_EXEC_PATH, "w") as f:
        f.write(wrapper)
    os.chmod(ROUTER_EXEC_PATH, 0o755)

    try:
        with open(URLS_PATH, "w") as f:
            f.write("\n".join(urls) + "\n")

        result = subprocess.run(
            [RUN_TESTS_SH_PATH], cwd=API_PROJECT_DIR, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert result.returncode == 0, (
            f"run_tests.sh failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(call_log), "run_tests.sh never invoked ./router"
        with open(call_log, "r") as f:
            calls = f.read().splitlines()
        assert calls == urls, f"Expected one router invocation per URL in order; got {calls!r}"

        assert os.path.isfile(TEST_REPORT_PATH), "run_tests.sh did not generate test_report.log"
        actual_lines = report_lines(TEST_REPORT_PATH)
        assert actual_lines == expected_lines, (
            "run_tests.sh did not report the dynamically supplied URLs and captured router output.\n"
            f"Expected: {expected_lines!r}\nGot: {actual_lines!r}"
        )
    finally:
        if os.path.lexists(ROUTER_EXEC_PATH):
            os.remove(ROUTER_EXEC_PATH)
        os.replace(real_router, ROUTER_EXEC_PATH)
        if os.path.exists(call_log):
            os.remove(call_log)
        with open(URLS_PATH, "wb") as f:
            f.write(original_urls)
        subprocess.run(
            [RUN_TESTS_SH_PATH], cwd=API_PROJECT_DIR,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )

    assert_report_matches(EXPECTED_REPORT)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
