#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import sqlite3
import stat
import subprocess

import pytest

PROJECT_DIR = "/home/user/project"
SETUP_SCRIPT = os.path.join(PROJECT_DIR, "setup_and_run.sh")
RUN_CALC_SCRIPT = os.path.join(PROJECT_DIR, "run_calc.sh")
API_HANDLER_SCRIPT = os.path.join(PROJECT_DIR, "api_handler.sh")
DB_PATH = os.path.join(PROJECT_DIR, "data.db")
MIGRATIONS_DIR = os.path.join(PROJECT_DIR, "migrations")
CALCULATOR = os.path.join(PROJECT_DIR, "bin", "calculator")
V1_DIR = os.path.realpath(os.path.join(PROJECT_DIR, "libs", "v1"))
V2_DIR = os.path.realpath(os.path.join(PROJECT_DIR, "libs", "v2"))

TOKEN = secrets.token_hex(8)
ORDER_TABLE = f"verifier_order_{TOKEN}"
ORDER_VALUE = secrets.randbelow(900000) + 100000


def run_command(argv, **kwargs):
    return subprocess.run(argv, capture_output=True, text=True, timeout=10, **kwargs)


def split_http_response(output):
    if "\r\n\r\n" in output:
        head, body = output.split("\r\n\r\n", 1)
        lines = head.split("\r\n")
    elif "\n\n" in output:
        head, body = output.split("\n\n", 1)
        lines = head.split("\n")
    else:
        pytest.fail(f"Response has no HTTP header/body separator: {output!r}")
    return lines, body


@pytest.fixture(scope="session", autouse=True)
def run_setup_script():
    """Ensure the setup script exists, is executable, and run it."""
    assert os.path.isfile(SETUP_SCRIPT), f"Setup script missing: {SETUP_SCRIPT}"
    assert os.access(SETUP_SCRIPT, os.X_OK), f"Setup script is not executable: {SETUP_SCRIPT}"

    # Force setup_and_run.sh to build the database itself. Add two migrations in
    # reverse creation order so only alphabetical application succeeds.
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    later = os.path.join(MIGRATIONS_DIR, f"04_verifier_insert_{TOKEN}.sql")
    earlier = os.path.join(MIGRATIONS_DIR, f"03_verifier_create_{TOKEN}.sql")
    with open(later, "w") as f:
        f.write(f"INSERT INTO {ORDER_TABLE} (value) VALUES ({ORDER_VALUE});\n")
    with open(earlier, "w") as f:
        f.write(f"CREATE TABLE {ORDER_TABLE} (value INTEGER NOT NULL);\n")

    result = run_command([SETUP_SCRIPT], cwd=PROJECT_DIR)
    assert result.returncode == 0, (
        f"Setup script failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )


def test_db_migration():
    """Test that the database migrations were applied correctly."""
    assert os.path.isfile(DB_PATH), f"Database file missing: {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT factor FROM settings;")
        row = cursor.fetchone()
        assert row is not None, "No data found in 'settings' table."
        assert row[0] == 7, f"Expected factor to be 7, got {row[0]}."
    except sqlite3.OperationalError as e:
        pytest.fail(f"Database query failed, migrations might not be applied correctly: {e}")
    finally:
        conn.close()


def test_all_migrations_are_applied_in_alphabetical_order():
    conn = sqlite3.connect(DB_PATH)
    try:
        row = conn.execute(f"SELECT value FROM {ORDER_TABLE}").fetchone()
        assert row == (ORDER_VALUE,), (
            "The dynamically added migrations were not all applied in alphabetical order."
        )
    except sqlite3.OperationalError as e:
        pytest.fail(f"Ordered migration check failed: {e}")
    finally:
        conn.close()


def test_run_calc_wrapper():
    """Test that run_calc.sh correctly sets the environment and runs the calculator with v1 lib."""
    assert os.path.isfile(RUN_CALC_SCRIPT), f"Wrapper script missing: {RUN_CALC_SCRIPT}"
    assert os.access(RUN_CALC_SCRIPT, os.X_OK), f"Wrapper script is not executable: {RUN_CALC_SCRIPT}"

    result = run_command([RUN_CALC_SCRIPT, "5"])
    assert result.returncode == 0, f"run_calc.sh failed with return code {result.returncode}."

    output = result.stdout.strip()
    assert output == "10", f"Expected output '10' from run_calc.sh 5, got '{output}'."


@pytest.mark.parametrize("value", [0, -11, 13, 29])
def test_run_calc_wrapper_dynamic_inputs(value):
    result = run_command([RUN_CALC_SCRIPT, str(value)])
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == str(value * 2)


def test_wrapper_invokes_calculator_with_v1_environment(tmp_path):
    backup = tmp_path / "calculator.real"
    env_log = tmp_path / "ld_path"
    arg_log = tmp_path / "args"
    marker = str(secrets.randbelow(800000) + 100000)

    shutil.move(CALCULATOR, backup)
    try:
        with open(CALCULATOR, "w") as f:
            f.write(
                "#!/bin/sh\n"
                f"printf '%s' \"$LD_LIBRARY_PATH\" > '{env_log}'\n"
                f"printf '%s\\n%s\\n' \"$#\" \"$1\" > '{arg_log}'\n"
                f"printf '%s\\n' '{marker}'\n"
            )
        os.chmod(CALCULATOR, 0o755)

        argument = str(secrets.randbelow(700) + 31)
        result = run_command([RUN_CALC_SCRIPT, argument])
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == marker, "The wrapper did not execute bin/calculator."
        assert arg_log.read_text().splitlines() == ["1", argument], (
            "The wrapper did not pass its argument unchanged to calculator."
        )

        paths = [os.path.realpath(p) for p in env_log.read_text().split(":") if p]
        assert V1_DIR in paths, "The calculator was not given the v1 library directory."
        if V2_DIR in paths:
            assert paths.index(V1_DIR) < paths.index(V2_DIR), (
                "The v1 library directory must take precedence over v2."
            )
    finally:
        if os.path.exists(CALCULATOR):
            os.remove(CALCULATOR)
        shutil.move(backup, CALCULATOR)


def test_api_handler_valid_request():
    """Test that api_handler.sh correctly processes a valid GET /calculate request."""
    assert os.path.isfile(API_HANDLER_SCRIPT), f"API handler script missing: {API_HANDLER_SCRIPT}"
    assert os.access(API_HANDLER_SCRIPT, os.X_OK), f"API handler script is not executable: {API_HANDLER_SCRIPT}"

    http_request = "GET /calculate HTTP/1.1\r\nHost: localhost\r\n\r\n"
    result = run_command([API_HANDLER_SCRIPT], input=http_request)

    assert result.returncode == 0, f"api_handler.sh failed with return code {result.returncode}."

    output = result.stdout
    assert "HTTP/1.1 200 OK" in output, "Expected HTTP/1.1 200 OK in response."

    expected_json = '{"result": 14}'
    output_no_space = "".join(output.split())
    expected_no_space = "".join(expected_json.split())
    assert expected_no_space in output_no_space, f"Expected JSON body '{expected_json}' in response. Got: {output}"


def test_api_queries_database_and_invokes_wrapper(tmp_path):
    factor = secrets.randbelow(800) + 101
    marker = secrets.randbelow(800000) + 100001
    call_log = tmp_path / "wrapper_args"
    backup = tmp_path / "run_calc.real"

    conn = sqlite3.connect(DB_PATH)
    conn.execute("UPDATE settings SET factor = ?", (factor,))
    conn.commit()
    conn.close()

    shutil.move(RUN_CALC_SCRIPT, backup)
    try:
        with open(RUN_CALC_SCRIPT, "w") as f:
            f.write(
                "#!/bin/sh\n"
                f"printf '%s\\n%s\\n' \"$#\" \"$1\" > '{call_log}'\n"
                f"printf '%s\\n' '{marker}'\n"
            )
        os.chmod(RUN_CALC_SCRIPT, 0o755)

        request = "GET /calculate HTTP/1.1\r\nHost: dynamic.example\r\n\r\n"
        result = run_command([API_HANDLER_SCRIPT], input=request)
        assert result.returncode == 0, result.stderr
        lines, body = split_http_response(result.stdout)
        assert lines[0] == "HTTP/1.1 200 OK"
        assert json.loads(body.strip()) == {"result": marker}
        assert call_log.read_text().splitlines() == ["1", str(factor)], (
            "The API must query factor from data.db and pass it to run_calc.sh."
        )
    finally:
        if os.path.exists(RUN_CALC_SCRIPT):
            os.remove(RUN_CALC_SCRIPT)
        shutil.move(backup, RUN_CALC_SCRIPT)
        conn = sqlite3.connect(DB_PATH)
        conn.execute("UPDATE settings SET factor = 7")
        conn.commit()
        conn.close()


def test_api_handler_invalid_request():
    """Test that api_handler.sh correctly returns 404 for an invalid request."""
    assert os.path.isfile(API_HANDLER_SCRIPT), f"API handler script missing: {API_HANDLER_SCRIPT}"

    http_request = "GET /other HTTP/1.1\r\nHost: localhost\r\n\r\n"
    result = run_command([API_HANDLER_SCRIPT], input=http_request)

    output = result.stdout
    assert "HTTP/1.1 404 Not Found" in output, f"Expected HTTP/1.1 404 Not Found in response. Got: {output}"


@pytest.mark.parametrize("request", [
    "GET /other HTTP/1.1\r\nHost: localhost\r\n\r\n",
    "POST /calculate HTTP/1.1\r\nHost: localhost\r\n\r\n",
])
def test_404_has_empty_body(request):
    result = run_command([API_HANDLER_SCRIPT], input=request)
    assert result.returncode == 0, result.stderr
    lines, body = split_http_response(result.stdout)
    assert lines[0] == "HTTP/1.1 404 Not Found"
    assert body == "", f"The 404 response body must be empty, got {body!r}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
