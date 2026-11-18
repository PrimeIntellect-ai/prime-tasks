#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'REF_EOF' > /tmp/trusted_network_mc.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

uint32_t state = 1;

uint32_t xorshift32() {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

double rand_float() {
    return (double)xorshift32() / 4294967296.0;
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int seed = atoi(argv[1]);
    state = seed;

    int n = 50;
    int adj[50][50] = {0};
    int degrees[50] = {0};

    for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
            if (rand_float() < 0.3) {
                adj[i][degrees[i]++] = j;
                adj[j][degrees[j]++] = i;
            }
        }
    }

    int num_walks = 1000;
    long total_steps = 0;

    for (int w = 0; w < num_walks; w++) {
        int curr = 0;
        int steps = 0;
        while (curr != n - 1 && steps < 1000) {
            if (degrees[curr] == 0) break;
            int next_idx = xorshift32() % degrees[curr];
            curr = adj[curr][next_idx];
            steps++;
        }
        total_steps += steps;
    }

    printf("%d,%.2f\n", seed, (double)total_steps / num_walks);
    return 0;
}
REF_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
import pytest

BASE = "/home/user/ml_data"
SOURCE = os.path.join(BASE, "network_mc.c")
BINARY = os.path.join(BASE, "generate_features")
SCRIPT = os.path.join(BASE, "run_all.sh")
CSV = os.path.join(BASE, "training_data.csv")
REFERENCE_SOURCE = "/tmp/trusted_network_mc.c"
REFERENCE_BINARY = "/tmp/trusted_generate_features"
CANDIDATE_BINARY = "/tmp/candidate_generate_features"


def compile_c(source, output):
    try:
        subprocess.run(
            ["gcc", "-o", output, source, "-lm"],
            check=True,
            capture_output=True,
            timeout=30,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Failed to compile {source}: {exc.stderr.decode(errors='replace')}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Compilation of {source} timed out")


def run_program(path, seed):
    try:
        result = subprocess.run(
            [path, str(seed)],
            capture_output=True,
            text=True,
            check=True,
            timeout=15,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"{path} failed for seed {seed}: {exc.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"{path} timed out for seed {seed}")
    assert result.stderr == "", f"{path} wrote unexpected stderr for seed {seed}"
    return result.stdout.strip()


@pytest.fixture(scope="session")
def expected_lines():
    compile_c(REFERENCE_SOURCE, REFERENCE_BINARY)
    return [run_program(REFERENCE_BINARY, seed) for seed in range(101, 151)]


def test_generate_features_exists_and_executable():
    path = BINARY
    assert os.path.isfile(path), f"The executable {path} does not exist."
    assert os.access(path, os.X_OK), f"The file {path} is not executable."
    with open(path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "generate_features is not a compiled ELF executable."


def test_run_all_sh_exists_and_executable():
    path = SCRIPT
    assert os.path.isfile(path), f"The script {path} does not exist."
    assert os.access(path, os.X_OK), f"The script {path} is not executable."


def test_source_compiles_and_matches_trusted_implementation(expected_lines):
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    compile_c(SOURCE, CANDIDATE_BINARY)
    actual = [run_program(CANDIDATE_BINARY, seed) for seed in range(101, 151)]
    assert actual == expected_lines, "The supplied C source no longer implements the required computation."


def test_generate_features_behavior(expected_lines):
    actual = [run_program(BINARY, seed) for seed in range(101, 151)]
    assert actual == expected_lines, "generate_features does not produce the required features."


def test_training_data_csv_content(expected_lines):
    assert os.path.isfile(CSV), f"The file {CSV} does not exist."
    with open(CSV, "r") as handle:
        raw_lines = handle.read().splitlines()
    assert len(raw_lines) == 50, f"Expected exactly 50 lines in {CSV}, found {len(raw_lines)}."
    assert all(line.strip() for line in raw_lines), "training_data.csv contains a blank line."
    lines = [line.strip() for line in raw_lines]
    assert lines == expected_lines, "The contents of training_data.csv do not match the trusted output for seeds 101 to 150."


def test_run_all_invokes_generator_for_every_required_seed():
    # Temporarily instrument both the executable and source so the script is
    # exercised even if it recompiles before running the seed loop.
    tracked = [SOURCE, BINARY, CSV]
    saved = {}
    for path in tracked:
        if os.path.exists(path):
            with open(path, "rb") as handle:
                saved[path] = (handle.read(), stat.S_IMODE(os.stat(path).st_mode))
        else:
            saved[path] = None

    nonce = secrets.token_hex(16)
    log_path = f"/tmp/generator_calls_{nonce}.log"
    wrapper = b'''#!/bin/bash\nprintf '%s\\n' "$1" >> "$VERIFY_LOG"\nprintf '%s,%s\\n' "$1" "$VERIFY_NONCE"\n'''
    instrument_c = b'''#include <stdio.h>\n#include <stdlib.h>\nint main(int argc, char **argv) {\n    if (argc != 2) return 1;\n    const char *log = getenv("VERIFY_LOG");\n    const char *nonce = getenv("VERIFY_NONCE");\n    if (!log || !nonce) return 2;\n    FILE *f = fopen(log, "a");\n    if (!f) return 3;\n    fprintf(f, "%s\\n", argv[1]);\n    fclose(f);\n    printf("%s,%s\\n", argv[1], nonce);\n    return 0;\n}\n'''

    try:
        with open(BINARY, "wb") as handle:
            handle.write(wrapper)
        os.chmod(BINARY, 0o755)
        with open(SOURCE, "wb") as handle:
            handle.write(instrument_c)
        os.chmod(SOURCE, 0o666)
        if os.path.exists(CSV):
            os.remove(CSV)
        open(log_path, "w").close()

        env = os.environ.copy()
        env["VERIFY_LOG"] = log_path
        env["VERIFY_NONCE"] = nonce
        try:
            subprocess.run(
                [SCRIPT],
                cwd=BASE,
                env=env,
                check=True,
                capture_output=True,
                text=True,
                timeout=45,
            )
        except subprocess.CalledProcessError as exc:
            pytest.fail(f"run_all.sh failed: {exc.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail("run_all.sh timed out")

        with open(log_path, "r") as handle:
            calls = handle.read().splitlines()
        expected_seeds = [str(seed) for seed in range(101, 151)]
        assert calls == expected_seeds, "run_all.sh did not invoke generate_features exactly once for each seed 101 through 150."

        assert os.path.isfile(CSV), "run_all.sh did not create training_data.csv."
        with open(CSV, "r") as handle:
            generated = handle.read().splitlines()
        expected_generated = [f"{seed},{nonce}" for seed in range(101, 151)]
        assert generated == expected_generated, "run_all.sh did not append each generator output to training_data.csv in order."
    finally:
        for path, value in saved.items():
            if value is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                data, mode = value
                with open(path, "wb") as handle:
                    handle.write(data)
                os.chmod(path, mode)
        if os.path.exists(log_path):
            os.remove(log_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
