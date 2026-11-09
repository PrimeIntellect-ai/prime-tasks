#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess
import tempfile
import uuid

CYPHER_PATH = "/home/user/etl/import.cypher"
JSON_PATH = "/home/user/data/orders.json"
SOURCE_PATH = "/home/user/etl/generate_cypher.cpp"
USER_INDEX = "CREATE INDEX user_id_index FOR (u:User) ON (u.user_id);"
PRODUCT_INDEX = "CREATE INDEX product_id_index FOR (p:Product) ON (p.product_id);"


def read_cypher():
    with open(CYPHER_PATH, "r") as f:
        return f.read()


def assert_exact_index_prefix(content):
    lines = content.splitlines()
    assert len(lines) >= 2, "Cypher output must begin with two index statements"
    assert lines[0] == USER_INDEX, "The user index must be the exact first statement"
    assert lines[1] == PRODUCT_INDEX, "The product index must be the exact second statement"


def test_import_cypher_exists():
    path = CYPHER_PATH
    assert os.path.isfile(path), f"File {path} does not exist. The C++ program must output the Cypher script here."


def test_index_statements():
    path = CYPHER_PATH
    content = read_cypher()

    user_index = USER_INDEX
    product_index = PRODUCT_INDEX

    assert user_index in content, f"Missing or incorrect user index statement in {path}"
    assert product_index in content, f"Missing or incorrect product index statement in {path}"
    assert_exact_index_prefix(content)


def test_cypher_merge_statements():
    path = CYPHER_PATH
    content = read_cypher()

    with open(JSON_PATH, "r") as f:
        orders = json.load(f)

    for order in orders:
        user_id = order["user_id"]
        user_name = order["user_name"]

        user_pattern = re.compile(rf'MERGE\s*\(\w+:User\s*\{{\s*user_id:\s*"{re.escape(user_id)}"\s*\}}\)\s*ON\s+CREATE\s+SET\s+\w+\.name\s*=\s*"{re.escape(user_name)}"', re.IGNORECASE)
        assert user_pattern.search(content), f"Missing or incorrect MERGE statement for User {user_id}"

        for purchase in order["purchases"]:
            product_id = purchase["product_id"]
            category = purchase["category"]
            price = float(purchase["price"])
            quantity = int(purchase["quantity"])

            product_pattern = re.compile(rf'MERGE\s*\(\w+:Product\s*\{{\s*product_id:\s*"{re.escape(product_id)}"\s*\}}\)\s*ON\s+CREATE\s+SET\s+\w+\.category\s*=\s*"{re.escape(category)}"', re.IGNORECASE)
            assert product_pattern.search(content), f"Missing or incorrect MERGE statement for Product {product_id}"

            if price.is_integer():
                price_str = rf"{int(price)}(?:\.0+)?"
            else:
                price_str = str(price).rstrip('0')
                if price_str.endswith('.'):
                    price_str += '0'
                price_str = price_str.replace('.', r'\.') + r"0*"

            rel_pattern = re.compile(rf'MERGE\s*\(\w+\)-\[\w*:PURCHASED\s*\{{\s*(?:price:\s*{price_str}\s*,\s*quantity:\s*{quantity}|quantity:\s*{quantity}\s*,\s*price:\s*{price_str})\s*\}}\]->\(\w+\)', re.IGNORECASE)
            assert rel_pattern.search(content), f"Missing or incorrect MERGE statement for PURCHASED edge from {user_id} to {product_id} (price: {price}, quantity: {quantity})"


NUMBER = r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?'
USER_STMT = re.compile(
    r'^\s*MERGE\s*\((?P<node>\w+):User\s*\{\s*user_id:\s*"(?P<id>[^"]*)"\s*\}\)'
    r'\s*ON\s+CREATE\s+SET\s+(?P<setnode>\w+)\.name\s*=\s*"(?P<name>[^"]*)"\s*$',
    re.IGNORECASE,
)
PRODUCT_STMT = re.compile(
    r'^\s*MERGE\s*\((?P<node>\w+):Product\s*\{\s*product_id:\s*"(?P<id>[^"]*)"\s*\}\)'
    r'\s*ON\s+CREATE\s+SET\s+(?P<setnode>\w+)\.category\s*=\s*"(?P<category>[^"]*)"\s*$',
    re.IGNORECASE,
)
REL_STMT = re.compile(
    rf'^\s*MERGE\s*\((?P<user>\w+)\)-\[\w*:PURCHASED\s*\{{\s*'
    rf'(?:price:\s*(?P<price1>{NUMBER})\s*,\s*quantity:\s*(?P<qty1>\d+)'
    rf'|quantity:\s*(?P<qty2>\d+)\s*,\s*price:\s*(?P<price2>{NUMBER}))'
    rf'\s*\}}\]->\((?P<product>\w+)\)\s*$',
    re.IGNORECASE,
)


def assert_relationship_endpoints(content, orders):
    user_bindings = {}
    product_bindings = {}
    relationships = []

    for statement in content.split(';'):
        statement = statement.strip()
        if not statement:
            continue

        match = USER_STMT.fullmatch(statement)
        if match:
            assert match.group("node") == match.group("setnode"), "User properties must be set on the merged User variable"
            user_bindings[match.group("node")] = (match.group("id"), match.group("name"))
            continue

        match = PRODUCT_STMT.fullmatch(statement)
        if match:
            assert match.group("node") == match.group("setnode"), "Product properties must be set on the merged Product variable"
            product_bindings[match.group("node")] = (match.group("id"), match.group("category"))
            continue

        match = REL_STMT.fullmatch(statement)
        if match:
            user_var = match.group("user")
            product_var = match.group("product")
            assert user_var in user_bindings, f"PURCHASED relationship uses unbound User variable {user_var}"
            assert product_var in product_bindings, f"PURCHASED relationship uses unbound Product variable {product_var}"
            price = float(match.group("price1") or match.group("price2"))
            quantity = int(match.group("qty1") or match.group("qty2"))
            relationships.append((user_bindings[user_var][0], product_bindings[product_var][0], price, quantity))

    for order in orders:
        for purchase in order["purchases"]:
            expected = (order["user_id"], purchase["product_id"], float(purchase["price"]), int(purchase["quantity"]))
            assert any(
                actual[0] == expected[0]
                and actual[1] == expected[1]
                and math.isclose(actual[2], expected[2], rel_tol=1e-9, abs_tol=1e-9)
                and actual[3] == expected[3]
                for actual in relationships
            ), f"Missing PURCHASED relationship connecting {expected[0]} to {expected[1]} with price {expected[2]} and quantity {expected[3]}"


def test_program_compiles_reads_json_and_generates_connected_relationships():
    assert os.path.isfile(SOURCE_PATH), f"C++ source file {SOURCE_PATH} does not exist"
    assert os.path.getsize(SOURCE_PATH) > 0, f"C++ source file {SOURCE_PATH} is empty"

    token = uuid.uuid4().hex
    orders = [
        {
            "user_id": f"U_{token}_A",
            "user_name": f"Generated User A {token}",
            "purchases": [
                {"product_id": f"P_{token}_X", "category": f"Category X {token}", "price": 41.37, "quantity": 3},
                {"product_id": f"P_{token}_Y", "category": f"Category Y {token}", "price": 208.5, "quantity": 7},
            ],
        },
        {
            "user_id": f"U_{token}_B",
            "user_name": f"Generated User B {token}",
            "purchases": [
                {"product_id": f"P_{token}_X", "category": f"Category X {token}", "price": 19.25, "quantity": 11},
            ],
        },
    ]

    with open(JSON_PATH, "rb") as f:
        original_json = f.read()
    original_output = None
    if os.path.exists(CYPHER_PATH):
        with open(CYPHER_PATH, "rb") as f:
            original_output = f.read()

    fd, executable = tempfile.mkstemp(prefix="generate_cypher_", dir="/tmp")
    os.close(fd)
    os.unlink(executable)

    try:
        compile_result = subprocess.run(
            ["g++", "-std=c++17", SOURCE_PATH, "-o", executable],
            cwd="/home/user/etl",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        assert compile_result.returncode == 0, f"generate_cypher.cpp did not compile:\n{compile_result.stderr}"

        with open(JSON_PATH, "w") as f:
            json.dump(orders, f)
        if os.path.exists(CYPHER_PATH):
            os.unlink(CYPHER_PATH)

        run_result = subprocess.run(
            [executable],
            cwd="/home/user/etl",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert run_result.returncode == 0, f"Compiled generator failed:\n{run_result.stderr}"
        assert os.path.isfile(CYPHER_PATH), "Running the compiled generator did not create import.cypher"

        generated = read_cypher()
        assert_exact_index_prefix(generated)
        assert_relationship_endpoints(generated, orders)
    finally:
        with open(JSON_PATH, "wb") as f:
            f.write(original_json)
        if original_output is None:
            if os.path.exists(CYPHER_PATH):
                os.unlink(CYPHER_PATH)
        else:
            with open(CYPHER_PATH, "wb") as f:
                f.write(original_output)
        if os.path.exists(executable):
            os.unlink(executable)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
