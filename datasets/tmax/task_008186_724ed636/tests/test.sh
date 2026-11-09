#!/bin/bash
set -e
mkdir -p /logs/verifier

ORIGINAL_DATA="/tmp/verifier-original-data-$$"
DYNAMIC_META="/tmp/verifier-dynamic-meta-$$.json"
MEM_DATA="/tmp/verifier-memory-data-$$"
MEM_HELPER="/tmp/verifier-memcheck-$$.go"

cleanup() {
    rm -rf /home/user/data
    if [ -e "$ORIGINAL_DATA" ]; then
        mv "$ORIGINAL_DATA" /home/user/data
    fi
    rm -rf "$MEM_DATA" "$DYNAMIC_META" "$MEM_HELPER"
}
trap cleanup EXIT

run_checks() {
    test -f /home/user/logprocessor/processor/process.go || return 1

    # Retain the original source-level assertion against the known leak.
    python3 - <<'PY' || return 1
import re
path = "/home/user/logprocessor/processor/process.go"
with open(path, "r") as f:
    content = f.read()
assignment_match = re.search(r'MemoryLeakCache\[.+?\]\s*=', content)
assert not assignment_match, "MemoryLeakCache is still being populated in process.go"
PY

    mv /home/user/data "$ORIGINAL_DATA" || return 1
    mkdir -p /home/user/data || return 1

    # Recreate the canonical fixture so prewritten output files cannot pass.
    python3 - <<'PY' || return 1
from pathlib import Path
root = Path('/home/user/data')
for i in range(1, 201):
    value = i % 10
    (root / f'log_{i}.csv').write_text((f'id,{value}\n') * 1000)
(root / 'bad log.csv').write_text('bad_data_no_comma\n')
PY
    rm -f /home/user/processed_output.txt /home/user/corrupted_files.txt
    (cd /home/user/logprocessor && timeout 90s go run main.go) || return 1

    # Preserve the original exact output assertions, now checked after execution.
    python3 - <<'PY' || return 1
from pathlib import Path
out = Path('/home/user/processed_output.txt')
bad = Path('/home/user/corrupted_files.txt')
assert out.is_file(), 'processed_output.txt was not created'
assert out.read_text().strip() == '900000', 'canonical sum is incorrect'
assert bad.is_file(), 'corrupted_files.txt was not created'
assert bad.read_text().strip() == '/home/user/data/bad log.csv', 'canonical corrupted-file output is incorrect'
PY

    # Exercise the compiled service on unpredictable names and values. A file with
    # any unparsable line must be rejected in full rather than partially summed.
    rm -rf /home/user/data
    mkdir -p /home/user/data
    python3 - "$DYNAMIC_META" <<'PY' || return 1
import json, secrets, sys
from pathlib import Path
root = Path('/home/user/data')
tag = secrets.token_hex(8)
values1 = [secrets.randbelow(100000) + 1, -(secrets.randbelow(5000) + 1), secrets.randbelow(70000) + 3]
values2 = [secrets.randbelow(90000) + 11, secrets.randbelow(60000) + 7]
(root / f'valid {tag}.csv').write_text(''.join(f'item,{v}\n' for v in values1))
(root / f'another-{tag}.csv').write_text(''.join(f'item,{v},extra\n' for v in values2))
bad1 = root / f'broken no comma {tag}.csv'
bad2 = root / f'broken-number-{tag}.csv'
bad1.write_text('item,999999\nmalformed_line\nitem,888888\n')
bad2.write_text('item,12345\nitem,not-an-integer\n')
json.dump({'sum': sum(values1) + sum(values2),
           'bad': sorted([str(bad1), str(bad2)])}, open(sys.argv[1], 'w'))
PY
    rm -f /home/user/processed_output.txt /home/user/corrupted_files.txt
    (cd /home/user/logprocessor && timeout 90s go run main.go) || return 1
    python3 - "$DYNAMIC_META" <<'PY' || return 1
import json, sys
from pathlib import Path
meta = json.load(open(sys.argv[1]))
out = Path('/home/user/processed_output.txt')
bad = Path('/home/user/corrupted_files.txt')
assert out.is_file(), 'dynamic run did not create processed_output.txt'
assert out.read_text().strip() == str(meta['sum']), 'dynamic sum is incorrect'
assert bad.is_file(), 'dynamic run did not create corrupted_files.txt'
actual = sorted(line.strip() for line in bad.read_text().splitlines() if line.strip())
assert actual == meta['bad'], f'incorrect corrupted paths: {actual!r}'
PY

    # Measure retained heap after processing a fresh, sizable directory. The known
    # cache retains essentially all input bytes, while a streaming/non-retaining
    # implementation releases them after GC.
    mkdir -p "$MEM_DATA"
    python3 - "$MEM_DATA" <<'PY' || return 1
import sys
from pathlib import Path
root = Path(sys.argv[1])
line = 'row,123456\n'
for i in range(96):
    (root / f'bulk-{i:03d}.csv').write_text(line * 22000)
PY
    cat > "$MEM_HELPER" <<'GO' || return 1
package main

import (
    "fmt"
    "logprocessor/processor"
    "os"
    "runtime"
    "runtime/debug"
    "strconv"
)

func main() {
    if len(os.Args) != 4 { os.Exit(2) }
    expected, err := strconv.Atoi(os.Args[2])
    if err != nil { panic(err) }
    totalBytes, err := strconv.ParseUint(os.Args[3], 10, 64)
    if err != nil { panic(err) }

    runtime.GC()
    debug.FreeOSMemory()
    var before runtime.MemStats
    runtime.ReadMemStats(&before)

    got := processor.ProcessLogs(os.Args[1])
    if got != expected {
        panic(fmt.Sprintf("bulk sum: got %d want %d", got, expected))
    }

    runtime.GC()
    debug.FreeOSMemory()
    var after runtime.MemStats
    runtime.ReadMemStats(&after)
    var retained uint64
    if after.HeapAlloc > before.HeapAlloc {
        retained = after.HeapAlloc - before.HeapAlloc
    }
    if retained >= totalBytes/3 {
        panic(fmt.Sprintf("heap retained %d bytes from %d bytes of input", retained, totalBytes))
    }
}
GO
    EXPECTED=$((96 * 22000 * 123456))
    TOTAL_BYTES=$(du -sb "$MEM_DATA" | awk '{print $1}')
    rm -f /home/user/corrupted_files.txt
    (cd /home/user/logprocessor && timeout 120s go run "$MEM_HELPER" "$MEM_DATA" "$EXPECTED" "$TOTAL_BYTES") || return 1
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
