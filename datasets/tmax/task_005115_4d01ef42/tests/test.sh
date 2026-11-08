#!/bin/bash
set +e
mkdir -p /logs/verifier

run_verification() {
    # Preserve the original artifact-existence assertions before rebuilding anything.
    [ -f /home/user/join_data.sh ] || return 1
    [ -f /home/user/infer.c ] || return 1
    [ -f /home/user/infer_model ] || return 1
    [ -x /home/user/infer_model ] || return 1

    # Execute the submitted script and executable rather than trusting pre-created outputs.
    rm -f /home/user/joined_sensor_data.csv /home/user/predictions.csv /home/user/benchmark.txt
    bash /home/user/join_data.sh || return 1
    /home/user/infer_model || return 1

    cat > /tmp/check_original.py <<'PY'
import math
import os
import re

joined = "/home/user/joined_sensor_data.csv"
assert os.path.isfile(joined), f"File {joined} is missing."
with open(joined) as f:
    lines = [line.strip() for line in f if line.strip()]
assert lines[0] == "id,temperature,vibration", f"Header of {joined} is incorrect."
assert lines[1:] == [
    "1,22.5,1.1",
    "2,45.1,4.8",
    "3,18.0,0.9",
    "4,60.2,5.5",
    "5,30.5,2.0",
], f"Data in {joined} does not match expected joined data."

predictions = "/home/user/predictions.csv"
assert os.path.isfile(predictions), f"File {predictions} is missing."
with open(predictions) as f:
    lines = [line.strip() for line in f if line.strip()]
assert lines[0] == "id,probability,class", f"Header of {predictions} is incorrect."
inputs = [
    (1, 22.5, 1.1),
    (2, 45.1, 4.8),
    (3, 18.0, 0.9),
    (4, 60.2, 5.5),
    (5, 30.5, 2.0),
]
expected = []
for ident, temperature, vibration in inputs:
    z = 0.5 * temperature + 1.2 * vibration - 15.0
    probability = 1.0 / (1.0 + math.exp(-z))
    expected.append(f"{ident},{probability:.4f},{1 if probability > 0.5 else 0}")
assert lines[1:] == expected, "Predictions do not match mathematically expected values."

benchmark = "/home/user/benchmark.txt"
assert os.path.isfile(benchmark), f"File {benchmark} is missing."
with open(benchmark) as f:
    content = f.read().strip()
assert re.match(r"^Inference Time:\s*\d+\s*us$", content), \
    f"Content of {benchmark} ('{content}') does not match expected format."
PY
    python3 /tmp/check_original.py || return 1

    # Rebuild the requested executable from the submitted source so the source itself
    # must implement the pipeline.
    gcc -O2 -o /home/user/infer_model /home/user/infer.c -lm || return 1
    [ -x /home/user/infer_model ] || return 1

    # Generate a fresh, unpredictable sorted fixture with non-overlapping IDs too.
    python3 - <<'PY' || return 1
import json
import math
import random
import struct

rng = random.SystemRandom()
while True:
    common = sorted(rng.sample(range(110, 190), 9))
    temp_only = sorted(rng.sample([x for x in range(101, 200) if x not in common], 3))
    vib_only = sorted(rng.sample([x for x in range(201, 260)], 3))
    values = {}
    safe = True
    for ident in common:
        t = rng.randint(120, 690) / 10.0
        v = rng.randint(2, 85) / 10.0
        # Avoid rare four-decimal rounding differences between valid float parsing
        # and the verifier's double-precision calculation.
        tf = struct.unpack('f', struct.pack('f', t))[0]
        vf = struct.unpack('f', struct.pack('f', v))[0]
        p = 1.0 / (1.0 + math.exp(-(0.5*t + 1.2*v - 15.0)))
        pf = 1.0 / (1.0 + math.exp(-(0.5*tf + 1.2*vf - 15.0)))
        if f"{p:.4f}" != f"{pf:.4f}" or ((p > 0.5) != (pf > 0.5)):
            safe = False
            break
        values[ident] = (f"{t:.1f}", f"{v:.1f}", p)
    if safe:
        break

all_temp = sorted(common + temp_only)
all_vib = sorted(common + vib_only)
with open('/home/user/sensor_temp.csv', 'w') as f:
    f.write('id,temperature\n')
    for ident in all_temp:
        temperature = values[ident][0] if ident in values else f"{rng.randint(100,700)/10.0:.1f}"
        f.write(f"{ident},{temperature}\n")
with open('/home/user/sensor_vib.csv', 'w') as f:
    f.write('id,vibration\n')
    for ident in all_vib:
        vibration = values[ident][1] if ident in values else f"{rng.randint(1,90)/10.0:.1f}"
        f.write(f"{ident},{vibration}\n")

expected_joined = [f"{ident},{values[ident][0]},{values[ident][1]}" for ident in common]
expected_predictions = []
for ident in common:
    probability = values[ident][2]
    expected_predictions.append(
        f"{ident},{probability:.4f},{1 if probability > 0.5 else 0}"
    )
with open('/tmp/dynamic_expected.json', 'w') as f:
    json.dump({'joined': expected_joined, 'predictions': expected_predictions}, f)
PY

    rm -f /home/user/joined_sensor_data.csv /home/user/predictions.csv /home/user/benchmark.txt
    bash /home/user/join_data.sh || return 1
    /home/user/infer_model || return 1

    python3 - <<'PY' || return 1
import json
import os
import re

with open('/tmp/dynamic_expected.json') as f:
    expected = json.load(f)
with open('/home/user/joined_sensor_data.csv') as f:
    joined = [line.strip() for line in f if line.strip()]
assert joined == ['id,temperature,vibration'] + expected['joined'], \
    'join_data.sh failed on the generated fixture'
with open('/home/user/predictions.csv') as f:
    predictions = [line.strip() for line in f if line.strip()]
assert predictions == ['id,probability,class'] + expected['predictions'], \
    'infer.c failed on the generated fixture'
with open('/home/user/benchmark.txt') as f:
    benchmark = f.read().strip()
assert re.match(r'^Inference Time:\s*\d+\s*us$', benchmark), \
    'benchmark output has the wrong format'
PY

    # Interpose CLOCK_MONOTONIC with a known 123-microsecond interval. This proves
    # the benchmark is derived from two actual clock_gettime calls, not a digit literal.
    cat > /tmp/clock_probe.c <<'C'
#define _GNU_SOURCE
#include <time.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>

static int monotonic_calls = 0;

typedef int (*real_clock_fn)(clockid_t, struct timespec *);

int clock_gettime(clockid_t clock_id, struct timespec *tp) {
    if (clock_id == CLOCK_MONOTONIC) {
        int call = ++monotonic_calls;
        tp->tv_sec = 100;
        tp->tv_nsec = 100000000L + (long)(call - 1) * 123000L;
        int fd = open("/tmp/clock_calls", O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd >= 0) {
            write(fd, "1\n", 2);
            close(fd);
        }
        return 0;
    }
    static real_clock_fn real_clock = 0;
    if (!real_clock)
        real_clock = (real_clock_fn)dlsym(RTLD_NEXT, "clock_gettime");
    return real_clock(clock_id, tp);
}
C
    gcc -shared -fPIC -o /tmp/clock_probe.so /tmp/clock_probe.c -ldl || return 1
    rm -f /tmp/clock_calls /home/user/predictions.csv /home/user/benchmark.txt
    LD_PRELOAD=/tmp/clock_probe.so /home/user/infer_model || return 1

    python3 - <<'PY' || return 1
import re

with open('/tmp/clock_calls') as f:
    calls = [line for line in f if line.strip()]
assert len(calls) == 2, 'infer_model must bracket inference with two CLOCK_MONOTONIC calls'
with open('/home/user/benchmark.txt') as f:
    content = f.read().strip()
match = re.match(r'^Inference Time:\s*(\d+)\s*us$', content)
assert match, 'benchmark output has the wrong format'
assert int(match.group(1)) == 123, \
    'benchmark value was not calculated from the measured CLOCK_MONOTONIC interval'
PY
}

if run_verification; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
