#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import os
import random
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile

import pytest
from packaging.requirements import Requirement
from packaging.version import Version

REPO = "/home/user/math-ws-proxy"


def test_pyproject_toml_fixed_and_installable():
    path = os.path.join(REPO, "pyproject.toml")
    assert os.path.isfile(path), "pyproject.toml does not exist"

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "websockets" in content, "The 'websockets' dependency is missing from pyproject.toml"

    target = tempfile.mkdtemp(prefix="math-ws-install-")
    try:
        result = subprocess.run(
            [sys.executable, "-m", "pip", "install", ".", "--target", target, "--no-cache-dir"],
            cwd=REPO,
            capture_output=True,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, f"pip install . failed:\n{result.stdout}\n{result.stderr}"

        distributions = list(importlib.metadata.distributions(path=[target]))
        package_dist = next(
            (d for d in distributions if d.metadata.get("Name", "").lower().replace("_", "-") == "math-ws-proxy"),
            None,
        )
        assert package_dist is not None, "Installed metadata for math-ws-proxy was not found"

        requirements = [Requirement(r) for r in (package_dist.requires or [])]
        websocket_requirements = [r for r in requirements if r.name.lower().replace("_", "-") == "websockets"]
        assert websocket_requirements, "Installed package metadata does not declare websockets"
        requirement = websocket_requirements[0]
        assert any(s.operator == ">=" and Version(s.version) >= Version("10.0") for s in requirement.specifier), \
            f"websockets dependency must declare a >=10.0 lower bound, got {requirement}"

        websocket_dist = next(
            (d for d in distributions if d.metadata.get("Name", "").lower() == "websockets"),
            None,
        )
        assert websocket_dist is not None, "pip install . did not install websockets into the target"
        assert Version(websocket_dist.version) >= Version("10.0"), \
            f"Installed websockets version is too old: {websocket_dist.version}"
        assert os.path.isfile(os.path.join(target, "math_ws", "solver.py")), \
            "The src/math_ws package was not included in the installation"
    finally:
        shutil.rmtree(target, ignore_errors=True)


def test_solver_logic():
    src_path = os.path.join(REPO, "src")
    if src_path not in sys.path:
        sys.path.insert(0, src_path)

    try:
        from math_ws.solver import solve_diophantine
    except ImportError as e:
        pytest.fail(f"Could not import solve_diophantine: {e}")

    assert solve_diophantine(3, 4, 25) == (3, 4), "Failed for 3x + 4y = 25"
    assert solve_diophantine(5, 2, 12) == (2, 1), "Failed for 5x + 2y = 12"
    assert solve_diophantine(2, 4, 5) is None, "Failed for 2x + 4y = 5, should be None"
    assert solve_diophantine(10, 15, 100) == (1, 6), \
        "Failed for 10x + 15y = 100, should return smallest positive x"

    def expected_solution(a, b, c):
        for x in range(1, c // a + 1):
            remainder = c - a * x
            if remainder >= b and remainder % b == 0:
                return (x, remainder // b)
        return None

    rng = random.SystemRandom()
    cases = []
    for _ in range(120):
        a = rng.randint(1, 80)
        b = rng.randint(1, 80)
        x = rng.randint(1, 30)
        y = rng.randint(1, 30)
        cases.append((a, b, a * x + b * y))
    for _ in range(120):
        cases.append((rng.randint(1, 80), rng.randint(1, 80), rng.randint(1, 2000)))

    for a, b, c in cases:
        expected = expected_solution(a, b, c)
        actual = solve_diophantine(a, b, c)
        assert actual == expected, f"solve_diophantine({a}, {b}, {c}) returned {actual}, expected {expected}"


def create_legacy(rows):
    legacy_path = os.path.join(REPO, "legacy.db")
    if os.path.exists(legacy_path):
        os.remove(legacy_path)
    conn = sqlite3.connect(legacy_path)
    try:
        conn.execute("CREATE TABLE requests (id INTEGER PRIMARY KEY, equation TEXT)")
        conn.executemany("INSERT INTO requests (id, equation) VALUES (?, ?)", rows)
        conn.commit()
    finally:
        conn.close()


def run_migration_and_read():
    v2_path = os.path.join(REPO, "v2.db")
    if os.path.exists(v2_path):
        os.remove(v2_path)
    result = subprocess.run(
        [sys.executable, "migrate.py"],
        cwd=REPO,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"python migrate.py failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(v2_path), f"Database {v2_path} was not created"

    conn = sqlite3.connect(v2_path)
    try:
        schema = conn.execute("PRAGMA table_info(parsed_requests)").fetchall()
        assert [(r[1], r[2].upper(), r[5]) for r in schema] == [
            ("id", "INTEGER", 1),
            ("a", "INTEGER", 0),
            ("b", "INTEGER", 0),
            ("c", "INTEGER", 0),
        ], f"parsed_requests has the wrong schema: {schema}"
        return conn.execute("SELECT id, a, b, c FROM parsed_requests ORDER BY id ASC").fetchall()
    except sqlite3.OperationalError as e:
        pytest.fail(f"Failed to query parsed_requests table: {e}")
    finally:
        conn.close()


def test_v2_db_migration():
    base_input = [
        (1, "3x + 4y = 25"),
        (2, "5x + 2y = 12"),
        (3, "10x + 15y = 100"),
    ]
    expected_rows = [
        (1, 3, 4, 25),
        (2, 5, 2, 12),
        (3, 10, 15, 100),
    ]

    create_legacy(base_input)
    rows = run_migration_and_read()
    assert rows == expected_rows, f"Data in v2.db does not match expected parsed values. Got {rows}"

    rng = random.SystemRandom()
    dynamic_input = list(base_input)
    dynamic_expected = list(expected_rows)
    ids = rng.sample(range(20, 10000), 35)
    for row_id in ids:
        a = rng.randint(1, 100000)
        b = rng.randint(1, 100000)
        c = rng.randint(1, 10000000)
        dynamic_input.append((row_id, f"{a}x + {b}y = {c}"))
        dynamic_expected.append((row_id, a, b, c))

    create_legacy(dynamic_input)
    rows = run_migration_and_read()
    assert rows == sorted(dynamic_expected), \
        f"Migration did not parse all rows from the current legacy database. Got {rows}"


def active_config(content):
    return "\n".join(line.split("#", 1)[0] for line in content.splitlines())


def require_directive(content, pattern, message):
    assert re.search(pattern, content, flags=re.IGNORECASE | re.MULTILINE), message


def test_nginx_conf():
    conf_path = "/home/user/nginx.conf"
    assert os.path.isfile(conf_path), f"Nginx configuration {conf_path} does not exist"

    with open(conf_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "Upgrade $http_upgrade" in content, "Missing 'Upgrade $http_upgrade' in nginx.conf"
    assert "Connection" in content and "upgrade" in content.lower(), \
        "Missing 'Connection \"upgrade\"' in nginx.conf"
    assert "proxy_pass http://127.0.0.1:9000" in content or "proxy_pass http://localhost:9000" in content, \
        "Missing proxy_pass to port 9000"

    active = active_config(content)
    require_directive(active, r"^\s*pid\s+/tmp/nginx\.pid\s*;", "Missing pid /tmp/nginx.pid;")
    require_directive(active, r"^\s*error_log\s+/tmp/error\.log(?:\s+\w+)?\s*;", "Missing writable error_log /tmp/error.log;")
    require_directive(active, r"\bevents\s*\{", "Missing events block")
    require_directive(active, r"\bhttp\s*\{", "Missing http block")
    require_directive(active, r"\bserver\s*\{", "Missing server block")
    require_directive(active, r"^\s*access_log\s+/tmp/access\.log(?:\s+\S+)?\s*;", "Missing access_log /tmp/access.log;")
    require_directive(active, r"^\s*client_body_temp_path\s+/tmp/client_body\s*;", "Missing client_body_temp_path")
    require_directive(active, r"^\s*proxy_temp_path\s+/tmp/proxy_temp\s*;", "Missing proxy_temp_path")
    require_directive(active, r"^\s*fastcgi_temp_path\s+/tmp/fastcgi_temp\s*;", "Missing fastcgi_temp_path")
    require_directive(active, r"^\s*uwsgi_temp_path\s+/tmp/uwsgi_temp\s*;", "Missing uwsgi_temp_path")
    require_directive(active, r"^\s*scgi_temp_path\s+/tmp/scgi_temp\s*;", "Missing scgi_temp_path")
    require_directive(active, r"^\s*listen\s+8080(?:\s+[^;]+)?\s*;", "Server must listen on port 8080")
    require_directive(active, r"\blocation\s+/\s*\{", "Missing location / block")
    require_directive(active, r"^\s*proxy_pass\s+http://127\.0\.0\.1:9000\s*;", "Incorrect proxy_pass target")
    require_directive(active, r"^\s*proxy_set_header\s+Upgrade\s+\$http_upgrade\s*;", "Missing active WebSocket Upgrade header")
    require_directive(active, r"^\s*proxy_set_header\s+Connection\s+[\"']?upgrade[\"']?\s*;", "Missing active WebSocket Connection header")

    result = subprocess.run(["nginx", "-t", "-c", conf_path], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Nginx configuration test failed:\n{result.stderr}"
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
