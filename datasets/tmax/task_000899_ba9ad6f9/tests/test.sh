#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import subprocess

SCRIPT_PATH = '/home/user/analyze.sh'
OUTPUT_PATH = '/home/user/output.json'
NODES_PATH = '/home/user/nodes.csv'
EDGES_PATH = '/home/user/edges.csv'


def write_fixture(nodes, edges):
    with open(NODES_PATH, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['node_id', 'author_name', 'department'])
        writer.writerows(nodes)
    with open(EDGES_PATH, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['source_id', 'target_id', 'weight'])
        writer.writerows(edges)


def run_script():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'{SCRIPT_PATH} exited with status {result.returncode}. stderr: {result.stderr}'
    )
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            raise AssertionError(f"File {OUTPUT_PATH} does not contain valid JSON.")


def test_script_executes_and_processes_csv_inputs():
    # Preserve the original existence and executable assertions.
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    # Execute the script against the original fixture before applying the original
    # exact-result assertions.
    original_nodes = [
        [1, 'Alice', 'Physics'],
        [2, 'Bob', 'Physics'],
        [3, 'Charlie', 'Chemistry'],
        [4, 'Diana', 'Math'],
        [5, 'Eve', 'Chemistry'],
        [6, 'Frank', 'Biology'],
        [7, 'Grace', 'Biology'],
    ]
    original_edges = [
        [1, 2, 5], [1, 3, 2], [2, 3, 1], [3, 4, 3], [4, 5, 4],
        [6, 1, 2], [7, 6, 8], [6, 3, 5], [5, 6, 1],
    ]
    write_fixture(original_nodes, original_edges)
    data = run_script()

    assert isinstance(data, list), f"Expected a JSON array in {OUTPUT_PATH}, but got {type(data).__name__}."

    expected_data = [
        {
            'department': 'Biology',
            'top_partner': 'Chemistry',
            'total_external_weight': 7,
        },
        {
            'department': 'Chemistry',
            'top_partner': 'Math',
            'total_external_weight': 4,
        },
        {
            'department': 'Math',
            'top_partner': 'Chemistry',
            'total_external_weight': 4,
        },
        {
            'department': 'Physics',
            'top_partner': 'Chemistry',
            'total_external_weight': 3,
        },
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items, got {len(data)}."
    departments = [item.get('department') for item in data]
    assert departments == sorted(departments), 'The JSON array is not sorted alphabetically by department name.'
    sorted_data = sorted(data, key=lambda x: x.get('department', ''))
    for actual, expected in zip(sorted_data, expected_data):
        assert actual.get('department') == expected['department'], f"Expected department {expected['department']}, got {actual.get('department')}."
        assert actual.get('top_partner') == expected['top_partner'], f"Expected top_partner {expected['top_partner']} for {expected['department']}, got {actual.get('top_partner')}."
        assert actual.get('total_external_weight') == expected['total_external_weight'], f"Expected total_external_weight {expected['total_external_weight']} for {expected['department']}, got {actual.get('total_external_weight')}."

    # Exercise the submitted script on unpredictable fixtures so a hardcoded
    # output cannot pass. Expected aggregates are derived independently here.
    rng = random.SystemRandom()
    for case_number in range(2):
        token = secrets.token_hex(4)
        departments = [f'Dept_{letter}_{token}' for letter in 'ABCDEF']
        ids = rng.sample(range(100, 10000), len(departments) * 2)
        nodes = []
        dept_nodes = {}
        for i, department in enumerate(departments):
            pair = ids[2 * i:2 * i + 2]
            dept_nodes[department] = pair
            nodes.append([pair[0], f'Author_{case_number}_{i}_a', department])
            nodes.append([pair[1], f'Author_{case_number}_{i}_b', department])

        edges = []
        for i, department in enumerate(departments):
            own = dept_nodes[department]
            next_dept = departments[(i + 1) % len(departments)]
            other_dept = departments[(i + 2) % len(departments)]
            next_nodes = dept_nodes[next_dept]
            other_nodes = dept_nodes[other_dept]
            # Internal edges must be filtered. Multiple external edges to the
            # same department must be aggregated before selecting a partner.
            edges.append([own[0], own[1], rng.randint(10, 30)])
            edges.append([own[0], next_nodes[0], rng.randint(1, 9)])
            edges.append([own[1], next_nodes[1], rng.randint(1, 9)])
            edges.append([own[0], other_nodes[0], rng.randint(1, 9)])

        rng.shuffle(nodes)
        rng.shuffle(edges)

        node_departments = {str(row[0]): row[2] for row in nodes}
        totals = {}
        partner_totals = {}
        for source, target, weight in edges:
            source_dept = node_departments[str(source)]
            target_dept = node_departments[str(target)]
            if source_dept == target_dept:
                continue
            totals[source_dept] = totals.get(source_dept, 0) + weight
            partner_totals.setdefault(source_dept, {})[target_dept] = (
                partner_totals.setdefault(source_dept, {}).get(target_dept, 0) + weight
            )

        write_fixture(nodes, edges)
        actual_data = run_script()
        assert isinstance(actual_data, list), f"Expected a JSON array, got {type(actual_data).__name__}."
        assert len(actual_data) == len(totals), f"Expected {len(totals)} items, got {len(actual_data)}."
        actual_departments = [item.get('department') for item in actual_data]
        assert actual_departments == sorted(totals), 'The JSON array is not sorted alphabetically by department name.'

        for item in actual_data:
            assert isinstance(item, dict), 'Each array item must be a JSON object.'
            department = item.get('department')
            assert department in totals, f'Unexpected department {department}.'
            assert item.get('total_external_weight') == totals[department], (
                f'Wrong total_external_weight for {department}.'
            )
            maximum = max(partner_totals[department].values())
            valid_partners = {
                partner for partner, weight in partner_totals[department].items()
                if weight == maximum
            }
            assert item.get('top_partner') in valid_partners, (
                f"Wrong top_partner for {department}: {item.get('top_partner')}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
