#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import csv
import hashlib
import math
import os
import random
import re
import shutil
import subprocess
import tempfile

HOME = "/home/user"
DATA = os.path.join(HOME, "data")
CPP = os.path.join(HOME, "variant_fitter.cpp")
PLOT = os.path.join(HOME, "plot.py")
R_FILE = os.path.join(HOME, "r_value.txt")
CSV_FILE = os.path.join(HOME, "results.csv")
PNG_FILE = os.path.join(HOME, "fit_plot.png")
EXE = "/tmp/variant_fitter_verifier"
PRIMER = "ATGCGTACGTAGCTA"


def run(cmd, timeout=30):
    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    subprocess.run(cmd, cwd=HOME, env=env, check=True, timeout=timeout)


def fasta_sequences(path):
    sequences = []
    current = []
    with open(path, "r") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if line.startswith(">"):
                if current:
                    sequences.append("".join(current).upper())
                    current = []
            else:
                current.append(line)
    if current:
        sequences.append("".join(current).upper())
    return sequences


def matches_primer(sequence):
    n = len(PRIMER)
    for start in range(len(sequence) - n + 1):
        mismatches = sum(a != b for a, b in zip(sequence[start:start+n], PRIMER))
        if mismatches <= 1:
            return True
    return False


def actual_counts():
    result = []
    for day in range(1, 11):
        path = os.path.join(DATA, f"day_{day}.fasta")
        assert os.path.isfile(path), f"Missing input {path}"
        result.append(sum(matches_primer(s) for s in fasta_sequences(path)))
    return result


def simulate(v0, r):
    values = [float(v0)]
    v = float(v0)
    for step in range(1, 91):
        v += 0.1 * r * v * (1.0 - v / 10000.0)
        if step % 10 == 0:
            values.append(v)
    return values


def expected_fit(counts):
    best_r = None
    best_mse = None
    best_values = None
    for i in range(101):
        r = i / 100.0
        values = simulate(counts[0], r)
        mse = sum((float(a) - p) ** 2 for a, p in zip(counts, values)) / 10.0
        if best_mse is None or mse < best_mse:
            best_r = r
            best_mse = mse
            best_values = values
    return best_r, best_values


def validate_outputs():
    counts = actual_counts()
    best_r, predictions = expected_fit(counts)

    assert os.path.isfile(R_FILE), f"{R_FILE} is missing"
    with open(R_FILE, "r") as f:
        r_content = f.read().strip()
    assert re.fullmatch(r"\d+\.\d{2}", r_content), "r_value.txt must contain only a value with two decimals"
    assert r_content == f"{best_r:.2f}", f"Expected r {best_r:.2f}, got {r_content}"

    assert os.path.isfile(CSV_FILE), f"{CSV_FILE} is missing"
    with open(CSV_FILE, "r", newline="") as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ["Day", "Actual", "Predicted"], f"Incorrect CSV header: {rows[0] if rows else None}"
    assert len(rows) == 11, f"Expected 10 data rows, found {max(0, len(rows)-1)}"
    for i, row in enumerate(rows[1:]):
        assert len(row) == 3, f"Row {i+1} does not have 3 columns"
        day, actual, predicted = row
        assert int(day) == i + 1, f"Expected Day {i+1}, got {day}"
        assert int(actual) == counts[i], f"Expected Actual {counts[i]}, got {actual}"
        assert re.fullmatch(r"-?\d+\.\d{2}", predicted), f"Predicted value is not formatted to two decimals: {predicted}"
        assert math.isclose(float(predicted), predictions[i], abs_tol=0.011), \
            f"Incorrect prediction on day {i+1}: expected {predictions[i]:.2f}, got {predicted}"


def execute_fitter_and_validate():
    for path in (R_FILE, CSV_FILE):
        if os.path.lexists(path):
            os.remove(path)
    run([EXE])
    validate_outputs()


def execute_plot_and_validate():
    if os.path.lexists(PNG_FILE):
        os.remove(PNG_FILE)
    run(["python3", PLOT])
    assert os.path.isfile(PNG_FILE), f"{PNG_FILE} is missing"
    assert os.path.getsize(PNG_FILE) > 0, f"{PNG_FILE} is empty"
    with open(PNG_FILE, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "fit_plot.png is not a PNG file"
    import matplotlib.image as mpimg
    image = mpimg.imread(PNG_FILE)
    assert image.ndim in (2, 3) and image.shape[0] > 1 and image.shape[1] > 1, "Plot image is invalid"
    assert float(image.max()) > float(image.min()), "Plot image contains no visible graphical content"


def mutate(s, positions):
    chars = list(s)
    for pos in positions:
        chars[pos] = next(c for c in "ACGT" if c != chars[pos])
    return "".join(chars)


def make_challenge_data():
    rng = random.SystemRandom()
    true_r = rng.randint(18, 38) / 100.0
    v = float(rng.randint(20, 50))
    counts = []
    for day in range(10):
        if day:
            for _ in range(10):
                v += 0.1 * true_r * v * (1.0 - v / 10000.0)
        counts.append(max(1, int(round(v)) + rng.randint(-2, 2)))

    shutil.rmtree(DATA)
    os.makedirs(DATA)
    for day, count in enumerate(counts, 1):
        with open(os.path.join(DATA, f"day_{day}.fasta"), "w") as f:
            for i in range(count):
                if i % 3 == 0:
                    implanted = PRIMER
                else:
                    implanted = mutate(PRIMER, [rng.randrange(len(PRIMER))])
                f.write(f">challenge_match_{i}\nGGGGG{implanted}CCCCC\n")
            for i in range(11):
                p1, p2 = rng.sample(range(len(PRIMER)), 2)
                nonmatch = mutate(PRIMER, [p1, p2])
                f.write(f">challenge_noise_{i}\nTTTTT{nonmatch}AAAAA\n")


def main():
    assert os.path.isfile(CPP) and os.path.getsize(CPP) > 0, "variant_fitter.cpp is missing or empty"
    assert os.path.isfile(PLOT) and os.path.getsize(PLOT) > 0, "plot.py is missing or empty"

    run(["g++", "-O3", "variant_fitter.cpp", "-o", EXE], timeout=45)
    assert os.path.isfile(EXE) and os.access(EXE, os.X_OK), "Compilation did not create an executable"

    backup_root = tempfile.mkdtemp(prefix="variant_data_backup_")
    backup_data = os.path.join(backup_root, "data")
    shutil.copytree(DATA, backup_data)
    try:
        # Execute and check the submitted artifacts against the supplied FASTA data.
        execute_fitter_and_validate()
        execute_plot_and_validate()

        # Replace the inputs with an unpredictable second valid dataset, then derive
        # all expected counts and model values independently from those files.
        make_challenge_data()
        execute_fitter_and_validate()
        execute_plot_and_validate()
        with open(PNG_FILE, "rb") as f:
            first_plot_hash = hashlib.sha256(f.read()).digest()
        with open(CSV_FILE, "rb") as f:
            challenge_csv = f.read()

        # Confirm that plot.py reads results.csv rather than merely emitting a fixed image.
        with open(CSV_FILE, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["Day", "Actual", "Predicted"])
            for day in range(1, 11):
                writer.writerow([day, day * 700, f"{10000 - day * 650:.2f}"])
        execute_plot_and_validate()
        with open(PNG_FILE, "rb") as f:
            second_plot_hash = hashlib.sha256(f.read()).digest()
        assert first_plot_hash != second_plot_hash, "plot.py does not respond to changes in results.csv"
        with open(CSV_FILE, "wb") as f:
            f.write(challenge_csv)

        # Restore the supplied data and leave all requested final artifacts valid for it.
        shutil.rmtree(DATA)
        shutil.copytree(backup_data, DATA)
        execute_fitter_and_validate()
        execute_plot_and_validate()
    finally:
        if os.path.exists(backup_data):
            if os.path.exists(DATA):
                shutil.rmtree(DATA)
            shutil.copytree(backup_data, DATA)
        shutil.rmtree(backup_root, ignore_errors=True)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
