#!/bin/bash
set -e
mkdir -p /logs/verifier
SCORE=0
BACKUP=""
cleanup() {
    if [ -n "$BACKUP" ] && [ -e "$BACKUP" ]; then
        rm -f /app/integrator_bin
        mv "$BACKUP" /app/integrator_bin
    fi
    echo "$SCORE" > /logs/verifier/reward.txt
}
trap cleanup EXIT

BACKUP="/app/integrator_bin.verifier_real.$$"
mv /app/integrator_bin "$BACKUP"
rm -f /tmp/verifier_detector_map /tmp/verifier_detector_calls

cat > /tmp/verifier_integrator.c <<'C_EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <fcntl.h>
#include <unistd.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static double uniform01(void) {
    return ((double)rand() + 1.0) / ((double)RAND_MAX + 2.0);
}

static double normal01(void) {
    double u1 = uniform01();
    double u2 = uniform01();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
}

static unsigned path_hash(const char *s) {
    unsigned h = 2166136261u;
    while (*s) {
        h ^= (unsigned char)*s++;
        h *= 16777619u;
    }
    return h;
}

int main(int argc, char **argv) {
    if (argc != 3) return 1;

    int logfd = open("/tmp/verifier_detector_calls", O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (logfd >= 0) {
        dprintf(logfd, "%s\n", argv[1]);
        close(logfd);
    }

    int type = -1;
    FILE *map = fopen("/tmp/verifier_detector_map", "r");
    if (map) {
        char path[4096];
        int candidate;
        while (fscanf(map, "%4095s %d", path, &candidate) == 2) {
            if (strcmp(path, argv[1]) == 0) {
                type = candidate;
                break;
            }
        }
        fclose(map);
    }

    if (type < 0) {
        FILE *in = fopen(argv[1], "r");
        if (!in) return 1;
        if (fscanf(in, "%d", &type) != 1) {
            fclose(in);
            return 1;
        }
        fclose(in);
    }

    FILE *out = fopen(argv[2], "w");
    if (!out) return 1;
    srand(path_hash(argv[1]));
    for (int i = 0; i < 1000; ++i) {
        double value = normal01();
        if (type == 1) value *= 1.0 + i * 0.05;
        fprintf(out, "%.10f\n", value);
    }
    fclose(out);
    return 0;
}
C_EOF

gcc -O2 /tmp/verifier_integrator.c -o /app/integrator_bin -lm
chown root:root /app/integrator_bin
chmod 4755 /app/integrator_bin

rm -rf /tmp/detector_hidden /tmp/detector_hook
mkdir -p /tmp/detector_hidden /tmp/detector_hook
chmod 711 /tmp/detector_hidden
chmod 755 /tmp/detector_hook
cat > /tmp/detector_hook/sitecustomize.py <<'PY_EOF'
import os

_marker = os.environ.get("LIBDIST_MARKER")
try:
    import libdist
    _original_compute_distance = libdist.compute_distance

    def _recording_compute_distance(*args, **kwargs):
        if _marker:
            with open(_marker, "a", encoding="utf-8") as marker_file:
                marker_file.write("compute_distance\n")
        return _original_compute_distance(*args, **kwargs)

    libdist.compute_distance = _recording_compute_distance
except Exception:
    pass
PY_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.machinery
import os
import secrets
import subprocess

import pytest

SCRIPT_PATH = "/home/user/detector.py"
HIDDEN_DIR = "/tmp/detector_hidden"
MAP_PATH = "/tmp/verifier_detector_map"
CALL_LOG = "/tmp/verifier_detector_calls"
HOOK_DIR = "/tmp/detector_hook"


def test_detector_script_exists():
    """Verify that the detector script exists."""
    assert os.path.exists(SCRIPT_PATH), f"Detector script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."


def test_detector_accuracy():
    """Verify that the detector correctly classifies all clean and evil files."""
    assert os.path.exists(SCRIPT_PATH), "Detector script missing."

    clean_dir = "/app/data/clean"
    evil_dir = "/app/data/evil"
    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    clean_failed = []
    for path in clean_files:
        result = subprocess.run(["python3", SCRIPT_PATH, path], capture_output=True, timeout=20)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(path))

    evil_failed = []
    for path in evil_files:
        result = subprocess.run(["python3", SCRIPT_PATH, path], capture_output=True, timeout=20)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(path))

    error_messages = []
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected instead of accepted): {', '.join(clean_failed)}")
    if evil_failed:
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed (accepted instead of rejected): {', '.join(evil_failed)}")
    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_libdist_installed():
    """Verify that the libdist module is installed and importable."""
    try:
        result = subprocess.run(
            ["python3", "-c", "import libdist; print(libdist.__file__)"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, "libdist module is not installed or failed to import."
        module_path = result.stdout.strip().splitlines()[-1]
        assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
            "libdist is not an installed compiled extension."
    except Exception as exc:
        pytest.fail(f"Failed to check libdist installation: {exc}")


def test_hidden_trajectory_cases_and_required_execution():
    """Use neutral, unreadable inputs whose labels are only exposed through integrator output."""
    labels = [0] * 6 + [1] * 6
    secrets.SystemRandom().shuffle(labels)
    cases = []

    with open(MAP_PATH, "w", encoding="utf-8") as mapping:
        for label in labels:
            name = f"case_{secrets.token_hex(12)}.csv"
            path = os.path.join(HIDDEN_DIR, name)
            with open(path, "w", encoding="utf-8") as input_file:
                input_file.write(f"{label}\n")
            os.chmod(path, 0o600)
            mapping.write(f"{path} {label}\n")
            cases.append((path, label))
    os.chmod(MAP_PATH, 0o600)

    failures = []
    for index, (path, expected) in enumerate(cases):
        open(CALL_LOG, "w", encoding="utf-8").close()
        os.chmod(CALL_LOG, 0o600)

        marker = os.path.join(HIDDEN_DIR, f"marker_{index}_{secrets.token_hex(8)}")
        open(marker, "w", encoding="utf-8").close()
        os.chmod(marker, 0o666)

        command = [
            "runuser", "-u", "user", "--", "env",
            f"PYTHONPATH={HOOK_DIR}",
            f"LIBDIST_MARKER={marker}",
            "python3", SCRIPT_PATH, path,
        ]
        result = subprocess.run(command, capture_output=True, text=True, timeout=25)

        with open(CALL_LOG, "r", encoding="utf-8") as call_file:
            calls = [line.strip() for line in call_file if line.strip()]
        with open(marker, "r", encoding="utf-8") as marker_file:
            metric_calls = marker_file.read().splitlines()

        if result.returncode != expected:
            failures.append(f"{os.path.basename(path)} returned {result.returncode}, expected {expected}")
        if path not in calls:
            failures.append(f"{os.path.basename(path)} was not passed to /app/integrator_bin")
        if "compute_distance" not in metric_calls:
            failures.append(f"{os.path.basename(path)} did not call libdist.compute_distance")

    if failures:
        pytest.fail(" | ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    SCORE=1
fi
