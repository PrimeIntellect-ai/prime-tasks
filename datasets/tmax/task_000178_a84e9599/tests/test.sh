#!/bin/bash
set -e
mkdir -p /logs/verifier

if ! python3 - <<'PREP_EOF'
import os
import secrets
import subprocess

root = "/home/user/waf"
v1 = os.path.join(root, "db/v1_init.sql")
v2 = os.path.join(root, "db/v2_update.sql")
nonce = secrets.token_hex(16)

with open(v1, "rb") as f:
    old_v1 = f.read()
with open(v2, "rb") as f:
    old_v2 = f.read()

for path in ("waf.db", "libparser.so", "waf_binary", "test_report.txt"):
    try:
        os.remove(os.path.join(root, path))
    except FileNotFoundError:
        pass

try:
    with open(v1, "ab") as f:
        f.write(("\nCREATE TABLE verifier_migration_marker (value TEXT);\n").encode())
    with open(v2, "ab") as f:
        f.write(("\nINSERT INTO verifier_migration_marker(value) VALUES ('" + nonce + "');\n").encode())

    env = os.environ.copy()
    result = subprocess.run(
        ["/home/user/run_ci.sh"],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=240,
    )
    with open("/tmp/run_ci_output.txt", "w") as f:
        f.write(result.stdout)
    if result.returncode != 0:
        raise RuntimeError(f"run_ci.sh exited with {result.returncode}:\n{result.stdout}")
finally:
    with open(v1, "wb") as f:
        f.write(old_v1)
    with open(v2, "wb") as f:
        f.write(old_v2)

with open("/tmp/verifier_nonce.txt", "w") as f:
    f.write(nonce)
PREP_EOF
then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import sqlite3
import stat
import subprocess
import textwrap
import pytest

ROOT = "/home/user/waf"


def run(cmd, *, cwd=None, env=None, timeout=120):
    return subprocess.run(
        cmd,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=True,
    )


def runtime_env():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = ROOT + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
    return env


def expected_output(payload):
    result = "BLOCKED" if payload == "DROP TABLE users;" else "ALLOWED"
    return f"Payload: {payload}, Result: {result}"


def test_db_schema():
    db_path = "/home/user/waf/waf.db"
    assert os.path.isfile(db_path), f"Database file missing: {db_path}"

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(rules);")
    columns = [row[1] for row in cursor.fetchall()]
    conn.close()

    assert "id" in columns, "Column 'id' missing in 'rules' table."
    assert "pattern" in columns, "Column 'pattern' missing in 'rules' table."
    assert "action" in columns, "Column 'action' missing in 'rules' table. Did you apply v2_update.sql?"


def test_migrations_were_actually_applied_in_order():
    with open("/tmp/verifier_nonce.txt") as f:
        nonce = f.read().strip()
    conn = sqlite3.connect(os.path.join(ROOT, "waf.db"))
    try:
        marker = conn.execute("SELECT value FROM verifier_migration_marker").fetchall()
        rule = conn.execute("SELECT pattern, action FROM rules WHERE pattern = ?", ("DROP TABLE",)).fetchone()
    finally:
        conn.close()
    assert marker == [(nonce,)], "run_ci.sh did not apply the verifier-modified v1 and v2 migration files in order"
    assert rule == ("DROP TABLE", "BLOCK"), "The migration-created rule or its v2 default is incorrect"


def test_c_memory_safety():
    parser_c = "/home/user/waf/c_src/parser.c"
    assert os.path.isfile(parser_c), f"Missing {parser_c}"

    with open(parser_c, "r") as f:
        content = f.read()

    assert "malloc(16)" not in content, "The C source file still contains the hardcoded malloc(16)."
    assert "strlen" in content or "strdup" in content, "The C source file should dynamically allocate memory using strlen or strdup."


def test_go_circular_import_resolved():
    config_go = "/home/user/waf/go_src/config/config.go"
    assert os.path.isfile(config_go), f"Missing {config_go}"

    with open(config_go, "r") as f:
        content = f.read()

    assert '"waf/engine"' not in content, "The config.go file still contains the circular import to waf/engine."


def test_ci_script_exists_and_executable():
    script_path = "/home/user/run_ci.sh"
    assert os.path.isfile(script_path), f"Missing CI script: {script_path}"

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()
    assert "set -e" in content, "The script must contain 'set -e' to fail immediately on errors."


def test_ci_script_contains_required_build_configuration():
    with open("/home/user/run_ci.sh") as f:
        content = f.read()
    assert "v1_init.sql" in content and "v2_update.sql" in content
    assert content.index("v1_init.sql") < content.index("v2_update.sql"), "v1 must be applied before v2"
    assert "-fsanitize=address" in content, "C compilation must enable AddressSanitizer"
    assert "-fPIC" in content, "C compilation must use position-independent code"
    assert "CGO_CFLAGS" in content, "The Go build must set CGO_CFLAGS"
    assert "CGO_LDFLAGS" in content, "The Go build must set CGO_LDFLAGS"
    assert "go build" in content, "The script must build the Go application"
    assert "LD_LIBRARY_PATH" in content, "The script must set LD_LIBRARY_PATH when running the binary"


def test_build_artifacts_exist():
    lib_path = "/home/user/waf/libparser.so"
    bin_path = "/home/user/waf/waf_binary"

    assert os.path.isfile(lib_path), f"Shared library missing: {lib_path}"
    assert os.path.isfile(bin_path), f"Go binary missing: {bin_path}"

    st = os.stat(bin_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Go binary {bin_path} is not executable."


def test_artifacts_are_real_and_linked_correctly():
    lib_path = os.path.join(ROOT, "libparser.so")
    bin_path = os.path.join(ROOT, "waf_binary")

    lib_header = run(["readelf", "-h", lib_path]).stdout
    assert "DYN (Shared object file)" in lib_header, "libparser.so is not an ELF shared object"
    symbols = run(["nm", "-D", lib_path]).stdout
    assert "extract_payload" in symbols, "libparser.so does not export extract_payload"
    dynamic = run(["readelf", "-d", lib_path]).stdout
    undefined = run(["nm", "-D", lib_path]).stdout
    assert "libasan" in dynamic or "__asan" in undefined, "libparser.so is not instrumented with AddressSanitizer"

    bin_header = run(["readelf", "-h", bin_path]).stdout
    assert "EXEC (Executable file)" in bin_header or "DYN (Position-Independent Executable file)" in bin_header
    bin_dynamic = run(["readelf", "-d", bin_path]).stdout
    assert "libparser.so" in bin_dynamic, "waf_binary is not dynamically linked to libparser.so"
    run(["go", "version", "-m", bin_path])


def test_shared_library_handles_unpredictable_long_payload():
    harness = "/tmp/parser_harness.c"
    executable = "/tmp/parser_harness"
    with open(harness, "w") as f:
        f.write(textwrap.dedent(r'''\
            #include <stdlib.h>
            #include <string.h>
            #include "parser.h"
            int main(int argc, char **argv) {
                if (argc != 2) return 10;
                char *result = extract_payload(argv[1]);
                if (result == NULL) return 11;
                int bad = strcmp(result, argv[1]);
                free(result);
                return bad ? 12 : 0;
            }
        '''))
    run([
        "gcc", "-fsanitize=address", "-I" + os.path.join(ROOT, "c_src"),
        harness, "-L" + ROOT, "-Wl,-rpath," + ROOT, "-lparser", "-o", executable
    ])
    payload = "LONG_" + secrets.token_hex(180)
    run([executable, payload], env=runtime_env())


def test_go_sources_build_independently():
    output = "/tmp/waf_verify_build"
    try:
        os.remove(output)
    except FileNotFoundError:
        pass
    env = runtime_env()
    env["CGO_CFLAGS"] = "-I" + os.path.join(ROOT, "c_src")
    env["CGO_LDFLAGS"] = "-L" + ROOT + " -lparser -fsanitize=address"
    run(["go", "build", "-o", output, "."], cwd=os.path.join(ROOT, "go_src"), env=env, timeout=180)
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    payload = "verify_" + secrets.token_hex(40)
    result = run([output, payload], env=runtime_env())
    assert result.stdout.strip() == expected_output(payload)


def test_binary_functionality_on_derived_inputs():
    binary = os.path.join(ROOT, "waf_binary")
    payloads = [
        "DROP TABLE users;",
        "DROP TABLE users; " + secrets.token_hex(8),
        "safe_" + secrets.token_hex(24),
        "x" * 128 + secrets.token_hex(32),
    ]
    for payload in payloads:
        result = run([binary, payload], env=runtime_env())
        assert result.stdout.strip() == expected_output(payload), result.stderr


def test_test_report_output():
    report_path = "/home/user/waf/test_report.txt"
    assert os.path.isfile(report_path), f"Test report missing: {report_path}"

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected = "Payload: DROP TABLE users;, Result: BLOCKED"
    assert expected in content, f"Test report does not contain the expected output. Found: {content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
