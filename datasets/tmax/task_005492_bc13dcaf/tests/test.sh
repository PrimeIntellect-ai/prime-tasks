#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import subprocess
import tempfile


def test_crash_tx_file():
    path = "/home/user/crash_tx.txt"
    assert os.path.isfile(path), f"File {path} does not exist. Did you create it?"

    with open(path, "r") as f:
        content = f.read().strip()

    assert "TXN-8842" in content, f"Expected 'TXN-8842' in {path}, but found '{content}'"
    assert content == "TXN-8842", f"{path} must contain only 'TXN-8842', but found '{content}'"


def test_rust_fix_compiles_and_works():
    src_dir = "/home/user/parser"
    assert os.path.isdir(src_dir), f"Directory {src_dir} does not exist."

    with tempfile.TemporaryDirectory() as tmpdir:
        test_project = os.path.join(tmpdir, "parser")
        shutil.copytree(src_dir, test_project)

        main_rs_path = os.path.join(test_project, "src", "main.rs")
        assert os.path.isfile(main_rs_path), "src/main.rs is missing from the parser project"

        rng = random.SystemRandom()
        cases = [
            ([], None),
            ([7], None),
            ([50, 50, 1, 2, 3], None),
            ([0, 0, 11, 22], 0),
            ([2, 0, 11, 22], 2),
            ([0, 1, 11, 22, 33], 2),
        ]

        def packet(a, b, length):
            data = [rng.randrange(256) for _ in range(length)]
            data[0] = a
            data[1] = b
            return data

        # Valid packets must return the exact suffix selected by a + 2*b.
        for _ in range(48):
            a = rng.randrange(256)
            b = rng.randrange(256)
            header_len = a + 2 * b
            length = max(2, header_len + rng.randrange(1, 33))
            cases.append((packet(a, b, length), header_len))

        # Exercise the equality boundary: only strictly greater lengths are OOB.
        for _ in range(16):
            while True:
                a = rng.randrange(256)
                b = rng.randrange(256)
                header_len = a + 2 * b
                if header_len >= 2:
                    break
            cases.append((packet(a, b, header_len), header_len))

        # Random malformed packets whose computed header lies beyond the packet.
        for _ in range(48):
            a = rng.randrange(3, 256)
            b = rng.randrange(256)
            header_len = a + 2 * b
            length = rng.randrange(2, header_len)
            cases.append((packet(a, b, length), None))

        rust_cases = []
        for data, expected_start in cases:
            values = ", ".join(str(value) for value in data)
            expected = "None" if expected_start is None else f"Some({expected_start}usize)"
            rust_cases.append(f"        (vec![{values}], {expected}),")

        test_code = r'''
#[cfg(test)]
mod verifier_tests {
    use super::extract_payload;

    #[test]
    fn test_oob_graceful_handling() {
        let bad_packet = vec![50, 50, 1, 2, 3];
        let res = extract_payload(&bad_packet);
        assert_eq!(res.len(), 0, "Expected empty slice for out-of-bounds header_len");
    }

    #[test]
    fn test_formula_payload_and_randomized_bounds() {
        let cases: Vec<(Vec<u8>, Option<usize>)> = vec![
''' + "\n".join(rust_cases) + r'''
        ];

        for (index, (packet, expected_start)) in cases.iter().enumerate() {
            let result = extract_payload(packet);
            match expected_start {
                Some(start) => assert_eq!(
                    result,
                    &packet[*start..],
                    "case {} did not return the exact payload suffix",
                    index
                ),
                None => assert!(
                    result.is_empty(),
                    "case {} should return an empty slice for a short or out-of-bounds packet",
                    index
                ),
            }
        }
    }
}
'''
        with open(main_rs_path, "a") as f:
            f.write("\n" + test_code)

        result = subprocess.run(
            ["cargo", "test"],
            cwd=test_project,
            capture_output=True,
            text=True,
        )

        assert result.returncode == 0, (
            "The Rust project failed to compile or did not implement the required extraction and bounds behavior.\n"
            f"STDOUT:\n{result.stdout}\n"
            f"STDERR:\n{result.stderr}\n"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
