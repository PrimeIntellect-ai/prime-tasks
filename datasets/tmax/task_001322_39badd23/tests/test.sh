#!/bin/bash
set +e
mkdir -p /logs/verifier
status=0

if ! pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1; then
    service postgresql start >/dev/null 2>&1 || status=1
fi

runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d postgres -c "ALTER USER postgres PASSWORD 'password';" >/dev/null 2>&1 || status=1
if ! runuser -u postgres -- psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='rbac_db'" 2>/dev/null | grep -q 1; then
    runuser -u postgres -- createdb rbac_db >/dev/null 2>&1 || status=1
fi

runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d rbac_db >/dev/null 2>&1 <<'SQL_EOF' || status=1
DROP TABLE IF EXISTS user_roles, role_permissions, permissions, roles, users CASCADE;

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL UNIQUE
);
CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    role_name TEXT NOT NULL UNIQUE,
    parent_role_id INTEGER REFERENCES roles(id)
);
CREATE TABLE permissions (
    id SERIAL PRIMARY KEY,
    resource_name TEXT NOT NULL UNIQUE
);
CREATE TABLE role_permissions (
    role_id INTEGER NOT NULL REFERENCES roles(id),
    permission_id INTEGER NOT NULL REFERENCES permissions(id),
    PRIMARY KEY (role_id, permission_id)
);
CREATE TABLE user_roles (
    user_id INTEGER NOT NULL REFERENCES users(id),
    role_id INTEGER NOT NULL REFERENCES roles(id),
    PRIMARY KEY (user_id, role_id)
);

INSERT INTO users (id, username) VALUES
    (1, 'alice'), (2, 'bob'), (3, 'carol'), (4, 'no_roles');
INSERT INTO roles (id, role_name, parent_role_id) VALUES
    (1, 'employee', NULL),
    (2, 'auditor', 1),
    (3, 'finance_viewer', 2),
    (4, 'finance_analyst', 3),
    (5, 'senior_analyst', 4),
    (6, 'guest', NULL),
    (7, 'direct_special', NULL);
INSERT INTO permissions (id, resource_name) VALUES
    (1, 'financial_records'),
    (2, 'public_page'),
    (3, 'payroll');
INSERT INTO role_permissions (role_id, permission_id) VALUES
    (1, 2),
    (2, 1),
    (3, 1),
    (5, 1),
    (6, 2),
    (7, 3);
INSERT INTO user_roles (user_id, role_id) VALUES
    (1, 5),
    (2, 6),
    (3, 6),
    (3, 7);
SELECT setval(pg_get_serial_sequence('users', 'id'), (SELECT MAX(id) FROM users));
SELECT setval(pg_get_serial_sequence('roles', 'id'), (SELECT MAX(id) FROM roles));
SELECT setval(pg_get_serial_sequence('permissions', 'id'), (SELECT MAX(id) FROM permissions));
SQL_EOF

if ! redis-cli -h 127.0.0.1 -p 6379 ping >/dev/null 2>&1; then
    redis-server --daemonize yes >/dev/null 2>&1 || status=1
fi
redis-cli -h 127.0.0.1 -p 6379 FLUSHALL >/dev/null 2>&1 || status=1
redis-cli -h 127.0.0.1 -p 6379 ZADD access:financial_records 1700000000.25 alice 1600000000 bob 1800000000.5 ghost_user >/dev/null 2>&1 || status=1
redis-cli -h 127.0.0.1 -p 6379 ZADD access:public_page 1710000000 alice 1720000000 bob >/dev/null 2>&1 || status=1
redis-cli -h 127.0.0.1 -p 6379 ZADD access:payroll 1730000000.75 carol >/dev/null 2>&1 || status=1
redis-cli -h 127.0.0.1 -p 6379 ZADD access:unregistered_resource 1740000000 alice >/dev/null 2>&1 || status=1

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import socket
import uuid
import urllib.error
import urllib.parse
import urllib.request

import psycopg2
import redis

DB = dict(host="127.0.0.1", port=5432, dbname="rbac_db", user="postgres", password="password", connect_timeout=3)
EXPECTED_KEYS = {
    "username",
    "resource_name",
    "authorized",
    "granted_by_roles",
    "recent_access_timestamps",
}


def check_port_open(host, port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(2)
        try:
            sock.connect((host, port))
            return True
        except OSError:
            return False


def call_api(username, resource):
    query = urllib.parse.urlencode({"username": username, "resource": resource})
    url = "http://127.0.0.1:8080/audit?" + query
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            assert response.status == 200
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        raise AssertionError(f"Agent API returned HTTP {exc.code} for {url}") from exc
    except Exception as exc:
        raise AssertionError(f"Failed to fetch Agent API for {url}: {exc}") from exc
    try:
        data = json.loads(body)
    except Exception as exc:
        raise AssertionError(f"Agent returned invalid JSON for {url}: {body!r}") from exc
    assert isinstance(data, dict), f"Response must be a JSON object: {data!r}"
    assert set(data) == EXPECTED_KEYS, f"Response has incorrect keys: {data!r}"
    assert data["username"] == username
    assert data["resource_name"] == resource
    assert type(data["authorized"]) is bool
    assert isinstance(data["granted_by_roles"], list)
    assert all(isinstance(role, str) for role in data["granted_by_roles"])
    assert data["granted_by_roles"] == sorted(data["granted_by_roles"])
    assert isinstance(data["recent_access_timestamps"], list)
    assert all(isinstance(value, (int, float)) and not isinstance(value, bool)
               for value in data["recent_access_timestamps"])
    assert data["recent_access_timestamps"] == sorted(
        data["recent_access_timestamps"], reverse=True
    )
    assert len(data["recent_access_timestamps"]) <= 3
    return data


def derive_expected(username, resource):
    with psycopg2.connect(**DB) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id, role_name, parent_role_id FROM roles")
            roles = {row[0]: (row[1], row[2]) for row in cur.fetchall()}
            cur.execute(
                "SELECT ur.role_id FROM user_roles ur "
                "JOIN users u ON u.id = ur.user_id WHERE u.username = %s",
                (username,),
            )
            frontier = [row[0] for row in cur.fetchall()]
            resolved = set()
            for _ in range(6):
                next_frontier = []
                for role_id in frontier:
                    if role_id in resolved or role_id not in roles:
                        continue
                    resolved.add(role_id)
                    parent = roles[role_id][1]
                    if parent is not None:
                        next_frontier.append(parent)
                frontier = next_frontier
                if not frontier:
                    break
            cur.execute(
                "SELECT rp.role_id FROM role_permissions rp "
                "JOIN permissions p ON p.id = rp.permission_id "
                "WHERE p.resource_name = %s",
                (resource,),
            )
            permission_roles = {row[0] for row in cur.fetchall()}

    granting = sorted(roles[role_id][0] for role_id in resolved & permission_roles)
    score = redis.Redis(host="127.0.0.1", port=6379, decode_responses=True).zscore(
        "access:" + resource, username
    )
    timestamps = [] if score is None else [float(score)]
    return {
        "username": username,
        "resource_name": resource,
        "authorized": bool(granting),
        "granted_by_roles": granting,
        "recent_access_timestamps": timestamps,
    }


def test_submission_and_service_exist():
    assert os.path.isfile("/home/user/audit_api/app.py"), "Required app.py is missing"
    assert os.path.getsize("/home/user/audit_api/app.py") > 0, "app.py is empty"
    assert check_port_open("127.0.0.1", 8080), "Agent API is not running on port 8080"


def test_database_and_redis_derived_results():
    users = ["alice", "bob", "carol", "no_roles", "ghost_user"]
    resources = ["financial_records", "public_page", "payroll", "unregistered_resource"]
    for username in users:
        for resource in resources:
            assert call_api(username, resource) == derive_expected(username, resource)


def test_unpredictable_live_data_and_updates():
    token = uuid.uuid4().hex
    username = "verify_user_" + token
    resource = "verify_resource_" + token
    parent_name = "z_parent_" + token
    child_name = "a_child_" + token
    first_score = 1750000000.125
    second_score = 1760000000.875

    with psycopg2.connect(**DB) as conn:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO users (username) VALUES (%s) RETURNING id", (username,))
            user_id = cur.fetchone()[0]
            cur.execute("INSERT INTO roles (role_name) VALUES (%s) RETURNING id", (parent_name,))
            parent_id = cur.fetchone()[0]
            cur.execute(
                "INSERT INTO roles (role_name, parent_role_id) VALUES (%s, %s) RETURNING id",
                (child_name, parent_id),
            )
            child_id = cur.fetchone()[0]
            cur.execute("INSERT INTO permissions (resource_name) VALUES (%s) RETURNING id", (resource,))
            permission_id = cur.fetchone()[0]
            cur.execute("INSERT INTO user_roles (user_id, role_id) VALUES (%s, %s)", (user_id, child_id))
            cur.execute(
                "INSERT INTO role_permissions (role_id, permission_id) VALUES (%s, %s), (%s, %s)",
                (parent_id, permission_id, child_id, permission_id),
            )

    redis_client = redis.Redis(host="127.0.0.1", port=6379, decode_responses=True)
    redis_client.zadd("access:" + resource, {username: first_score})
    assert call_api(username, resource) == derive_expected(username, resource)

    with psycopg2.connect(**DB) as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM role_permissions WHERE permission_id = %s", (permission_id,))
    redis_client.zadd("access:" + resource, {username: second_score})

    updated = call_api(username, resource)
    assert updated == derive_expected(username, resource)
    assert updated["authorized"] is False
    assert updated["granted_by_roles"] == []
    assert updated["recent_access_timestamps"] == [second_score]
TEST_EOF

if [ "$status" -eq 0 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
