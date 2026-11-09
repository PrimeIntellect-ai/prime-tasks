#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import importlib.machinery
import os
import re
import shutil
import signal
import sqlite3
import subprocess
import sysconfig
import time

import pytest
import requests

ROOT = "/app/waf-service"
DB_PATH = os.path.join(ROOT, "db/rules.db")
SCHEMA_PATH = os.path.join(ROOT, "db/schema_v1.sql")
MIGRATE_PATH = os.path.join(ROOT, "migrate_db.sh")
VENDOR = os.path.join(ROOT, "vendor/http-parser-ext")
SERVER_PATH = os.path.join(ROOT, "server.py")


def test_rules_db_exists():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."


def test_rules_db_schema():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(signatures);")
    columns = cursor.fetchall()
    conn.close()

    assert len(columns) > 0, "Table 'signatures' does not exist or has no columns."
    column_names = [col[1] for col in columns]
    assert "rule_hash" in column_names, "Column 'rule_hash' is missing from 'signatures' table."


def test_service_running_and_responds():
    url = "http://127.0.0.1:8443/"
    for i in range(3):
        try:
            response = requests.get(url, timeout=2)
            break
        except requests.exceptions.RequestException:
            if i == 2:
                pytest.fail(f"Could not connect to service at {url}")
            time.sleep(1)

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    assert "WAF Active" in response.text, f"Expected 'WAF Active' in response body, got {response.text}"


def test_http_parser_ext_installed():
    try:
        subprocess.run(
            ["python3", "-c", "import http_parser_ext"],
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to import http_parser_ext in Python 3. Stderr: {e.stderr}")


def test_migrate_script_exists():
    assert os.path.isfile(MIGRATE_PATH), f"Migration script {MIGRATE_PATH} does not exist."


def test_migration_script_rebuilds_from_schema_and_alters_table(tmp_path):
    script = open(MIGRATE_PATH, encoding="utf-8").read()
    active = "\n".join(line for line in script.splitlines() if not line.lstrip().startswith("#"))
    assert re.search(r"schema_v1\.sql", active), "migrate_db.sh must read schema_v1.sql"
    assert re.search(
        r"ALTER\s+TABLE\s+signatures\s+ADD\s+(?:COLUMN\s+)?rule_hash\s+TEXT",
        active,
        re.IGNORECASE,
    ), "migrate_db.sh must execute the required ALTER TABLE statement"

    schema_backup = tmp_path / "schema_v1.sql"
    db_backup = tmp_path / "rules.db"
    shutil.copy2(SCHEMA_PATH, schema_backup)
    shutil.copy2(DB_PATH, db_backup)

    probe = "verifier_schema_probe"
    try:
        with open(SCHEMA_PATH, "a", encoding="utf-8") as f:
            f.write(f"\nCREATE TABLE {probe} (value TEXT);\n")
        for path in (DB_PATH, DB_PATH + "-wal", DB_PATH + "-shm", DB_PATH + "-journal"):
            if os.path.exists(path):
                os.remove(path)

        result = subprocess.run(
            ["bash", MIGRATE_PATH], cwd=ROOT, capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, f"migrate_db.sh failed:\n{result.stdout}\n{result.stderr}"
        assert os.path.isfile(DB_PATH), "migrate_db.sh did not create rules.db"

        with sqlite3.connect(DB_PATH) as conn:
            tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            columns = {row[1]: row[2].upper() for row in conn.execute("PRAGMA table_info(signatures)")}
        assert probe in tables, "migrate_db.sh did not apply the contents of schema_v1.sql"
        assert columns.get("rule_hash") == "TEXT", "migrate_db.sh did not add rule_hash as TEXT"
    finally:
        shutil.copy2(schema_backup, SCHEMA_PATH)
        for path in (DB_PATH, DB_PATH + "-wal", DB_PATH + "-shm", DB_PATH + "-journal"):
            if os.path.exists(path):
                os.remove(path)
        shutil.copy2(db_backup, DB_PATH)


def test_python3_build_configuration_and_native_rebuild():
    build_path = os.path.join(ROOT, "build.sh")
    makefile_path = os.path.join(VENDOR, "Makefile")
    setup_path = os.path.join(VENDOR, "setup.py")
    c_path = os.path.join(VENDOR, "http_parser_ext.c")

    for path in (build_path, makefile_path, setup_path, c_path):
        assert os.path.isfile(path), f"Required build file is missing: {path}"

    build_text = open(build_path, encoding="utf-8").read()
    build_active = "\n".join(line for line in build_text.splitlines() if not line.lstrip().startswith("#"))
    assert "python2" not in build_active.lower(), "build.sh still invokes Python 2"
    assert re.search(r"\bmake\b", build_active), "build.sh must run the vendored Makefile"
    assert re.search(r"\b(?:python3|pip3)\b", build_active), "build.sh must use Python 3 build/install commands"

    make_text = open(makefile_path, encoding="utf-8").read()
    assert "python2" not in make_text.lower(), "The vendored Makefile still references Python 2"
    assert "python3-config" in make_text, "The vendored Makefile must use python3-config"

    setup_tree = ast.parse(open(setup_path, encoding="utf-8").read(), filename=setup_path)
    setup_dump = ast.dump(setup_tree)
    assert "Extension" in setup_dump and "http_parser_ext.c" in setup_dump, \
        "setup.py must define a C extension built from http_parser_ext.c"

    for site_dir in {sysconfig.get_path("purelib"), sysconfig.get_path("platlib")}:
        if not site_dir:
            continue
        for candidate in glob.glob(os.path.join(site_dir, "http_parser_ext*")):
            if os.path.isdir(candidate) and not os.path.islink(candidate):
                shutil.rmtree(candidate)
            else:
                os.remove(candidate)
    shutil.rmtree(os.path.join(VENDOR, "build"), ignore_errors=True)
    for candidate in glob.glob(os.path.join(VENDOR, "http_parser_ext*.so")):
        os.remove(candidate)

    started = time.time()
    result = subprocess.run(
        ["bash", build_path], cwd=ROOT, capture_output=True, text=True, timeout=180
    )
    assert result.returncode == 0, f"build.sh failed:\n{result.stdout}\n{result.stderr}"

    check = subprocess.run(
        [
            "python3", "-I", "-c",
            "import importlib.machinery, os, http_parser_ext; "
            "assert isinstance(http_parser_ext.__loader__, importlib.machinery.ExtensionFileLoader); "
            "assert callable(http_parser_ext.parse_request); "
            "print(http_parser_ext.__file__)"
        ],
        cwd="/tmp", capture_output=True, text=True
    )
    assert check.returncode == 0, \
        f"build.sh did not install a native Python 3 extension:\n{check.stdout}\n{check.stderr}"
    origin = check.stdout.strip().splitlines()[-1]
    assert any(origin.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES)
    assert os.path.getmtime(origin) >= started - 2, "The native extension was not rebuilt by build.sh"


def _kill_listener(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, encoding="ascii") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].rsplit(":", 1)[1], 16) == port and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for proc_dir in glob.glob("/proc/[0-9]*"):
        try:
            for fd in os.listdir(os.path.join(proc_dir, "fd")):
                try:
                    target = os.readlink(os.path.join(proc_dir, "fd", fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(proc_dir.rsplit("/", 1)[1]))
        except (FileNotFoundError, PermissionError):
            continue
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if pids:
        time.sleep(0.5)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_server_is_python3_uses_parser_and_serves_when_executed():
    source = open(SERVER_PATH, encoding="utf-8").read()
    compile(source, SERVER_PATH, "exec")
    assert "urllib2" not in source, "server.py still uses urllib2"
    assert ".iteritems(" not in source, "server.py still uses dict.iteritems()"

    tree = ast.parse(source, filename=SERVER_PATH)
    imports_parser = any(
        (isinstance(node, ast.Import) and any(alias.name == "http_parser_ext" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "http_parser_ext")
        for node in ast.walk(tree)
    )
    calls_parser = any(
        isinstance(node, ast.Call)
        and ((isinstance(node.func, ast.Attribute) and node.func.attr == "parse_request")
             or (isinstance(node.func, ast.Name) and node.func.id == "parse_request"))
        for node in ast.walk(tree)
    )
    attrs = {node.attr for node in ast.walk(tree) if isinstance(node, ast.Attribute)}
    assert imports_parser and calls_parser, "server.py must use http_parser_ext.parse_request"
    assert {"accept", "recv"}.issubset(attrs), "server.py must read accepted HTTP socket data"
    assert any(isinstance(node, (ast.For, ast.While)) for node in ast.walk(tree)), \
        "server.py must retain a request-processing state loop"

    _kill_listener(8443)
    process = subprocess.Popen(
        ["python3", SERVER_PATH], cwd=ROOT,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        response = None
        for _ in range(20):
            assert process.poll() is None, "server.py exited instead of remaining active"
            try:
                response = requests.get("http://127.0.0.1:8443/", timeout=1)
                break
            except requests.exceptions.RequestException:
                time.sleep(0.2)
        assert response is not None, "Executing server.py did not open 127.0.0.1:8443"
        assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
        assert response.text == "WAF Active", f"Expected exact body 'WAF Active', got {response.text!r}"
        assert process.poll() is None, "server.py did not remain running after handling a request"
    except Exception:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
        raise
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
