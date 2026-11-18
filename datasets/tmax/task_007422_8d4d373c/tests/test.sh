#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def get_expected_results():
    # Recompute the expected results using standard python libraries
    # Since we can't use numpy, we will read the binary npy files manually or just use the known truth
    # Wait, the prompt says "Use only the Python standard library and pytest (no third-party libs)."
    # We can't use numpy. We must parse the npy files or just use the known seed if we could, but we can't use numpy.
    # However, we can use struct to parse the npy files.
    import struct

    def read_npy(filepath):
        with open(filepath, 'rb') as f:
            magic = f.read(6)
            if magic != b'\x93NUMPY':
                raise ValueError("Not a npy file")
            major, minor = struct.unpack('<BB', f.read(2))
            header_len = struct.unpack('<H', f.read(2))[0]
            header_str = f.read(header_len).decode('ascii')

            # very basic parsing of header dict
            header_str = header_str.strip()
            # find shape
            shape_start = header_str.find("'shape': (") + 10
            shape_end = header_str.find(")", shape_start)
            shape_tuple = header_str[shape_start:shape_end]
            shape = tuple(int(x.strip()) for x in shape_tuple.split(',') if x.strip())

            # read data
            data = f.read()
            # assume float64
            num_elements = 1
            for dim in shape:
                num_elements *= dim

            floats = struct.unpack('<' + 'd' * num_elements, data)

            # reshape
            result = []
            idx = 0
            for i in range(shape[0]):
                row = []
                for j in range(shape[1]):
                    row.append(floats[idx])
                    idx += 1
                result.append(row)
            return result

    items_A = read_npy('/home/user/data/experiment_A_items.npy')
    items_B = read_npy('/home/user/data/experiment_B_items.npy')
    queries = read_npy('/home/user/data/queries.npy')

    import math

    def l2_norm(vec):
        return math.sqrt(sum(x*x for x in vec if not math.isnan(x)))

    def normalize(matrix):
        res = []
        for row in matrix:
            norm = l2_norm(row)
            res.append([x / norm if norm > 0 else 0 for x in row])
        return res

    items_A_norm = normalize(items_A)
    items_B_norm = normalize(items_B)

    valid_queries_count = 0
    results = {
        "valid_queries_count": 0,
        "experiment_A": {},
        "experiment_B": {}
    }

    for i, q in enumerate(queries):
        if any(math.isnan(x) for x in q):
            continue

        valid_queries_count += 1
        q_norm_val = l2_norm(q)
        q_norm = [x / q_norm_val if q_norm_val > 0 else 0 for x in q]

        sim_A = [sum(a*b for a, b in zip(row, q_norm)) for row in items_A_norm]
        sim_B = [sum(a*b for a, b in zip(row, q_norm)) for row in items_B_norm]

        # argsort descending
        top3_A = sorted(range(len(sim_A)), key=lambda x: sim_A[x], reverse=True)[:3]
        top3_B = sorted(range(len(sim_B)), key=lambda x: sim_B[x], reverse=True)[:3]

        results["experiment_A"][str(i)] = top3_A
        results["experiment_B"][str(i)] = top3_B

    results["valid_queries_count"] = valid_queries_count
    return results

def test_results_file_exists():
    assert os.path.exists('/home/user/experiment_results.json'), "The file /home/user/experiment_results.json does not exist."

def test_results_content():
    with open('/home/user/experiment_results.json', 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file /home/user/experiment_results.json is not a valid JSON file.")

    expected_results = get_expected_results()

    assert "valid_queries_count" in results, "Missing 'valid_queries_count' in JSON."
    assert results["valid_queries_count"] == expected_results["valid_queries_count"], f"Expected valid_queries_count to be {expected_results['valid_queries_count']}, but got {results['valid_queries_count']}."

    assert "experiment_A" in results, "Missing 'experiment_A' in JSON."
    assert "experiment_B" in results, "Missing 'experiment_B' in JSON."

    for exp in ["experiment_A", "experiment_B"]:
        assert isinstance(results[exp], dict), f"'{exp}' should be a dictionary."
        assert len(results[exp]) == expected_results["valid_queries_count"], f"'{exp}' should contain {expected_results['valid_queries_count']} entries."

        for q_idx, top3 in expected_results[exp].items():
            assert q_idx in results[exp], f"Query index '{q_idx}' missing from '{exp}'."
            assert isinstance(results[exp][q_idx], list), f"Value for query '{q_idx}' in '{exp}' should be a list."
            assert len(results[exp][q_idx]) == 3, f"Value for query '{q_idx}' in '{exp}' should contain exactly 3 items."
            assert results[exp][q_idx] == top3, f"Top 3 items for query '{q_idx}' in '{exp}' do not match expected results."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
