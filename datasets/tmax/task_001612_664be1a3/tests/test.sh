#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import ast
import csv
import os
import re

import pytest
import requests
import pytesseract
from PIL import Image, ImageEnhance, ImageFilter

BASE_URL = "http://127.0.0.1:5050"
HEADERS = {"Authorization": "Bearer net-graph-secret"}


def load_expected_costs():
    """Independently derive every expected result from the supplied CSVs and image."""
    with Image.open("/app/cost_formula.png") as source:
        image = source.convert("L")
        image = image.resize((image.width * 4, image.height * 4), Image.Resampling.LANCZOS)
        image = ImageEnhance.Contrast(image).enhance(2.0)
        image = image.filter(ImageFilter.SHARPEN)
        formula_text = pytesseract.image_to_string(image, config="--psm 6")

    formulas = {}
    for line in formula_text.splitlines():
        match = re.search(r"\b(ROUTER|SWITCH|SERVER)\b\s*:\s*(.+)$", line, re.IGNORECASE)
        if match:
            formulas[match.group(1).upper()] = match.group(2).strip()

    assert set(formulas) == {"ROUTER", "SWITCH", "SERVER"}, (
        f"Could not extract all formulas from /app/cost_formula.png. OCR output: {formula_text!r}"
    )

    def evaluate(expression, metric_a, metric_b):
        expression = expression.lower().replace("×", "*")
        tree = ast.parse(expression, mode="eval")
        allowed_nodes = (
            ast.Expression,
            ast.BinOp,
            ast.Add,
            ast.Mult,
            ast.Name,
            ast.Load,
            ast.Constant,
        )
        assert all(isinstance(node, allowed_nodes) for node in ast.walk(tree)), (
            f"Unexpected formula syntax extracted from image: {expression!r}"
        )
        assert all(
            not isinstance(node, ast.Name) or node.id in {"metric_a", "metric_b"}
            for node in ast.walk(tree)
        ), f"Unexpected variable in extracted formula: {expression!r}"
        return float(eval(compile(tree, "<ocr-formula>", "eval"), {"__builtins__": {}}, {
            "metric_a": metric_a,
            "metric_b": metric_b,
        }))

    base_costs = {}
    with open("/app/nodes.csv", newline="") as handle:
        for row in csv.DictReader(handle):
            node_id = row["node_id"]
            node_type = row["node_type"].upper()
            assert node_type in formulas, f"No extracted formula for node type {node_type}"
            base_costs[node_id] = evaluate(
                formulas[node_type], float(row["metric_a"]), float(row["metric_b"])
            )

    neighbors = {node_id: set() for node_id in base_costs}
    with open("/app/edges.csv", newline="") as handle:
        for row in csv.DictReader(handle):
            source = row["source_id"]
            target = row["target_id"]
            assert source in base_costs and target in base_costs
            neighbors[source].add(target)
            neighbors[target].add(source)

    return {
        node_id: sum(base_costs[neighbor] for neighbor in adjacent)
        for node_id, adjacent in neighbors.items()
    }


EXPECTED_COSTS = load_expected_costs()


def test_server_ready_file():
    """Verify that the agent created the /tmp/server_ready file."""
    assert os.path.isfile("/tmp/server_ready"), "The file /tmp/server_ready was not found. Did you create it after starting the server?"


def test_api_neighborhood_n1():
    """Verify the neighborhood cost for N1."""
    url = f"{BASE_URL}/api/neighborhood/N1"
    try:
        response = requests.get(url, headers=HEADERS, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200 for N1, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert data.get("node_id") == "N1", f"Expected node_id 'N1', got {data.get('node_id')}"
    assert data.get("neighborhood_cost") == 46.0, f"Expected neighborhood_cost 46.0 for N1, got {data.get('neighborhood_cost')}"


def test_api_neighborhood_n4():
    """Verify the neighborhood cost for N4."""
    url = f"{BASE_URL}/api/neighborhood/N4"
    try:
        response = requests.get(url, headers=HEADERS, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200 for N4, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert data.get("node_id") == "N4", f"Expected node_id 'N4', got {data.get('node_id')}"
    assert data.get("neighborhood_cost") == 47.0, f"Expected neighborhood_cost 47.0 for N4, got {data.get('neighborhood_cost')}"


def test_api_all_nodes_from_resources():
    """Exercise every CSV node using answers derived from the image and graph resources."""
    assert EXPECTED_COSTS, "No nodes were loaded from /app/nodes.csv"
    for node_id, expected_cost in EXPECTED_COSTS.items():
        url = f"{BASE_URL}/api/neighborhood/{node_id}"
        try:
            response = requests.get(url, headers=HEADERS, timeout=5)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to the server at {url}: {e}")

        assert response.status_code == 200, (
            f"Expected status code 200 for {node_id}, got {response.status_code}. "
            f"Response: {response.text}"
        )
        data = response.json()
        assert data.get("node_id") == node_id, (
            f"Expected node_id {node_id!r}, got {data.get('node_id')!r}"
        )
        assert data.get("neighborhood_cost") == expected_cost, (
            f"Expected neighborhood_cost {expected_cost} for {node_id}, "
            f"got {data.get('neighborhood_cost')}"
        )


def test_api_unauthorized():
    """Verify that the API requires the correct Authorization header."""
    url = f"{BASE_URL}/api/neighborhood/N1"

    # Missing header
    try:
        response_missing = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}: {e}")
    assert response_missing.status_code in [401, 403], f"Expected 401 or 403 when missing Auth header, got {response_missing.status_code}"

    # Wrong token
    wrong_headers = {"Authorization": "Bearer wrong-secret"}
    try:
        response_wrong = requests.get(url, headers=wrong_headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}: {e}")
    assert response_wrong.status_code in [401, 403], f"Expected 401 or 403 with wrong Auth token, got {response_wrong.status_code}"


def test_api_not_found():
    """Verify that the API returns 404 for a non-existent node."""
    url = f"{BASE_URL}/api/neighborhood/N99"
    try:
        response = requests.get(url, headers=HEADERS, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}: {e}")

    assert response.status_code == 404, f"Expected status code 404 for non-existent node N99, got {response.status_code}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
