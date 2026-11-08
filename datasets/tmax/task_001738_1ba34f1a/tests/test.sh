#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import csv
import pytest

class Cell:
    def __init__(self, xmin, xmax, ymin, ymax, depth):
        self.xmin = xmin
        self.xmax = xmax
        self.ymin = ymin
        self.ymax = ymax
        self.depth = depth
        self.points = 0
        self.children = []

    def contains(self, x, y):
        x_match = (self.xmin <= x < self.xmax) if self.xmax < 1.0 else (self.xmin <= x <= 1.0)
        y_match = (self.ymin <= y < self.ymax) if self.ymax < 1.0 else (self.ymin <= y <= 1.0)
        return x_match and y_match

def build_tree(points):
    root_cells = [
        Cell(0.0, 0.5, 0.0, 0.5, 0),
        Cell(0.5, 1.0, 0.0, 0.5, 0),
        Cell(0.0, 0.5, 0.5, 1.0, 0),
        Cell(0.5, 1.0, 0.5, 1.0, 0)
    ]

    leaf_cells = []

    def process_cell(cell, pts):
        in_pts = [p for p in pts if cell.contains(p[0], p[1])]
        cell.points = len(in_pts)
        if cell.points > 50 and cell.depth < 3:
            xmid = (cell.xmin + cell.xmax) / 2.0
            ymid = (cell.ymin + cell.ymax) / 2.0
            cell.children = [
                Cell(cell.xmin, xmid, cell.ymin, ymid, cell.depth + 1),
                Cell(xmid, cell.xmax, cell.ymin, ymid, cell.depth + 1),
                Cell(cell.xmin, xmid, ymid, cell.ymax, cell.depth + 1),
                Cell(xmid, cell.xmax, ymid, cell.ymax, cell.depth + 1)
            ]
            for c in cell.children:
                process_cell(c, in_pts)
        else:
            leaf_cells.append(cell)

    for rc in root_cells:
        process_cell(rc, points)

    return leaf_cells

def gauss2d(x, y):
    return math.exp(-((x - 0.5)**2 + (y - 0.5)**2) / (2 * 0.2**2))

@pytest.fixture(scope="session")
def expected_results():
    data_path = '/home/user/spatial_data.csv'
    assert os.path.exists(data_path), f"File {data_path} is missing."

    pts = []
    with open(data_path, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                pts.append((float(row[0]), float(row[1])))

    leaves = build_tree(pts)
    total_points = sum(c.points for c in leaves)

    max_depth = max(c.depth for c in leaves)
    total_cells = len(leaves)

    q_primes = []
    for c in leaves:
        xc = (c.xmin + c.xmax) / 2.0
        yc = (c.ymin + c.ymax) / 2.0
        area = (c.xmax - c.xmin) * (c.ymax - c.ymin)
        q_primes.append(gauss2d(xc, yc) * area)

    sum_q_prime = sum(q_primes)
    Q = [qp / sum_q_prime for qp in q_primes]
    P = [c.points / total_points for c in leaves]

    kl = 0.0
    for p, q in zip(P, Q):
        if p > 0:
            kl += p * math.log(p / q)

    return {
        "total_cells": total_cells,
        "max_depth_reached": max_depth,
        "kl_divergence": round(kl, 4)
    }

@pytest.fixture(scope="session")
def student_results():
    json_path = '/home/user/model_fit.json'
    assert os.path.exists(json_path), f"The output file {json_path} was not created."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_path} does not contain valid JSON.")

    required_keys = ["total_cells", "max_depth_reached", "kl_divergence"]
    for k in required_keys:
        assert k in data, f"Key '{k}' is missing from {json_path}."

    return data

def test_total_cells(expected_results, student_results):
    expected = expected_results["total_cells"]
    student = student_results["total_cells"]
    assert student == expected, f"Expected total_cells to be {expected}, but got {student}."

def test_max_depth_reached(expected_results, student_results):
    expected = expected_results["max_depth_reached"]
    student = student_results["max_depth_reached"]
    assert student == expected, f"Expected max_depth_reached to be {expected}, but got {student}."

def test_kl_divergence(expected_results, student_results):
    expected = expected_results["kl_divergence"]
    student = student_results["kl_divergence"]
    assert abs(student - expected) <= 1e-3, f"Expected kl_divergence to be close to {expected}, but got {student}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
