#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_c_files_exist():
    c_file = '/home/user/compare_fasta_mc.c'
    exe_file = '/home/user/compare_fasta_mc'

    assert os.path.isfile(c_file), f"{c_file} is missing. C source code must be saved here."
    assert os.path.isfile(exe_file), f"{exe_file} is missing. The C program must be compiled to this path."
    assert os.access(exe_file, os.X_OK), f"{exe_file} is not executable."

def get_fasta_lengths(filepath):
    lengths = []
    with open(filepath, 'r') as f:
        current_len = 0
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith('>'):
                if current_len > 0:
                    lengths.append(current_len)
                    current_len = 0
            else:
                current_len += len(line)
        if current_len > 0:
            lengths.append(current_len)
    return lengths

def compute_expected_pvalue():
    ref_lens = get_fasta_lengths('/home/user/ref.fasta')
    query_lens = get_fasta_lengths('/home/user/query.fasta')

    N_ref = len(ref_lens)
    N_query = len(query_lens)
    pooled = ref_lens + query_lens
    N = len(pooled)

    mean_ref = sum(ref_lens) / N_ref
    mean_query = sum(query_lens) / N_query
    D_obs = abs(mean_ref - mean_query)

    state = 42
    def xorshift32():
        nonlocal state
        state ^= (state << 13) & 0xFFFFFFFF
        state ^= (state >> 17) & 0xFFFFFFFF
        state ^= (state << 5) & 0xFFFFFFFF
        return state

    count = 0
    permutations = 100000

    for _ in range(permutations):
        arr = list(pooled)
        for i in range(N - 1, 0, -1):
            j = xorshift32() % (i + 1)
            arr[i], arr[j] = arr[j], arr[i]

        m_ref = sum(arr[:N_ref]) / N_ref
        m_query = sum(arr[N_ref:]) / N_query
        D_perm = abs(m_ref - m_query)

        if round(D_perm, 6) >= round(D_obs, 6):
            count += 1

    return count / permutations

def test_pvalue_output():
    pvalue_file = '/home/user/pvalue.txt'
    assert os.path.isfile(pvalue_file), f"{pvalue_file} is missing."

    expected_pvalue = compute_expected_pvalue()
    expected_str = f"{expected_pvalue:.4f}"

    with open(pvalue_file, 'r') as f:
        actual_str = f.read().strip()

    assert actual_str == expected_str, f"Expected p-value {expected_str}, but got {actual_str} in {pvalue_file}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
