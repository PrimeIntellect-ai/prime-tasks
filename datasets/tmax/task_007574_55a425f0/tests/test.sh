#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/fast_bootstrap.sh"
FASTA_PATH = "/home/user/input.fasta"


def test_script_exists_and_executable():
    """Verify the script exists and has executable permissions."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def get_expected_output(fasta_path, seed):
    """Compute expected output independently with the required gawk sampling logic."""
    parse_program = r'''/^>/ {if (seqlen>0) print seqlen; seqlen=0; next} {seqlen+=length($0)} END {if(seqlen>0) print seqlen}'''
    lengths_out = subprocess.check_output(
        ["gawk", parse_program, fasta_path], text=True
    )

    with tempfile.TemporaryDirectory(prefix="bootstrap_oracle_") as workdir:
        lengths_path = os.path.join(workdir, "lengths.txt")
        means_path = os.path.join(workdir, "means.txt")
        with open(lengths_path, "w") as f:
            f.write(lengths_out)

        bootstrap_program = r'''
BEGIN {
    srand(seed)
}
{
    len[NR]=$1
}
END {
    n = NR
    sum_orig = 0
    for(i=1; i<=n; i++) sum_orig += len[i]
    orig_mean = sum_orig / n
    printf "Original Mean: %.2f\n", orig_mean

    for(b=1; b<=1000; b++) {
        sum = 0
        for(i=1; i<=n; i++) {
            idx = int(rand() * n) + 1
            sum += len[idx]
        }
        print (sum / n) > outfile
    }
}
'''
        out1 = subprocess.check_output(
            ["gawk", "-v", f"seed={seed}", "-v", f"outfile={means_path}",
             bootstrap_program, lengths_path],
            text=True,
        )
        sorted_means = subprocess.check_output(["sort", "-n", means_path], text=True)
        percentile_program = (
            'NR==25 {lower=$1} NR==975 {upper=$1} '
            'END {printf "95%% CI: %.2f to %.2f\\n", lower, upper}'
        )
        out2 = subprocess.run(
            ["awk", percentile_program], input=sorted_means,
            capture_output=True, text=True, check=True
        ).stdout

    return out1.strip() + "\n" + out2.strip()


def run_and_compare(fasta_path, seed):
    expected = get_expected_output(fasta_path, seed)
    result = subprocess.run(
        [SCRIPT_PATH, fasta_path, str(seed)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    actual = result.stdout.strip()
    assert actual == expected, (
        f"Output mismatch for {fasta_path} with seed {seed}.\n"
        f"Expected:\n{expected}\nActual:\n{actual}"
    )


def test_script_output_seed_123():
    """Preserve the original fixed-file test with seed 123."""
    run_and_compare(FASTA_PATH, 123)


def test_script_output_seed_42():
    """Preserve the original fixed-file test with seed 42."""
    run_and_compare(FASTA_PATH, 42)


def write_dynamic_fasta(path, lengths, rng):
    """Create a valid, irregularly wrapped FASTA with exactly the given lengths."""
    alphabet = "ACGT"
    with open(path, "w") as f:
        for record, length in enumerate(lengths):
            f.write(f">dynamic record {record} {secrets.token_hex(4)}\n")
            sequence = "".join(alphabet[(record + i) % 4] for i in range(length))
            position = 0
            while position < length:
                width = rng.randint(1, min(41, length - position))
                f.write(sequence[position:position + width] + "\n")
                position += width


def test_dynamic_fasta_files_and_seeds():
    """Exercise arbitrary FASTA contents, wrapping, sequence counts, and seeds."""
    rng = secrets.SystemRandom()
    length_sets = [
        [rng.randint(1, 40)],
        [rng.randint(1, 250) for _ in range(rng.randint(4, 11))],
        [rng.randint(20, 900) for _ in range(rng.randint(17, 37))],
    ]

    paths = []
    try:
        for lengths in length_sets:
            path = f"/tmp/dynamic_{secrets.token_hex(12)}.fasta"
            paths.append(path)
            write_dynamic_fasta(path, lengths, rng)
            seed = rng.randint(1, 2**31 - 1)
            run_and_compare(path, seed)
    finally:
        for path in paths:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
