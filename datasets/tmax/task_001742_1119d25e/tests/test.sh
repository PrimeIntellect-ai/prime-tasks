#!/bin/bash
set -u
mkdir -p /logs/verifier

DATA=/home/user/test_data.txt
BACKUP=/tmp/test_data.original
AUDIT=/tmp/benchmark_audit.jsonl
SITE_DIR=/tmp/benchmark_audit_site
RUN_STATUS=0

cp "$DATA" "$BACKUP"
restore_data() {
    cp "$BACKUP" "$DATA" 2>/dev/null || true
}
trap restore_data EXIT

python3 - <<'PY'
with open('/home/user/test_data.txt', 'w') as f:
    for i in range(1, 312):
        a = 11 + (i * 17) % 83
        b = 1 + (i * 7) % 13
        c = 1 + (i * 11) % 9
        if i % 3 == 0:
            expr = f"{a} + {b} * {c}"
        elif i % 3 == 1:
            expr = f"{a} * {b} + {c}"
        else:
            expr = f"{a} + {b} + {c}"
        f.write(expr + '\n')
    # Deliberate duplicate prime values test duplicate handling.
    f.write('97\n97\n89\n83\n79\n73\n')
PY

rm -f /home/user/qa_report.json "$AUDIT"
rm -rf "$SITE_DIR"
mkdir -p "$SITE_DIR"

cat > "$SITE_DIR/sitecustomize.py" <<'PY'
import json
import multiprocessing
import multiprocessing.queues
import os
import time
import tracemalloc
import uuid

_LOG = os.environ.get('BENCHMARK_AUDIT_LOG')

def emit(kind, **fields):
    if not _LOG:
        return
    record = {'kind': kind, 'pid': os.getpid(), 'time': time.monotonic_ns()}
    record.update(fields)
    try:
        raw = (json.dumps(record, sort_keys=True) + '\n').encode()
        fd = os.open(_LOG, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
        try:
            os.write(fd, raw)
        finally:
            os.close(fd)
    except Exception:
        pass

_orig_process = multiprocessing.Process
class AuditedProcess(_orig_process):
    def __init__(self, *args, **kwargs):
        target = kwargs.get('target')
        if target is None and len(args) > 1:
            target = args[1]
        target_name = getattr(target, '__qualname__', getattr(target, '__name__', repr(target)))
        emit('process_init', target=target_name)
        super().__init__(*args, **kwargs)

    def start(self):
        emit('process_start')
        result = super().start()
        emit('process_started', child_pid=self.pid)
        return result

multiprocessing.Process = AuditedProcess

_orig_queue_factory = multiprocessing.Queue
def audited_queue(*args, **kwargs):
    q = _orig_queue_factory(*args, **kwargs)
    q._benchmark_audit_qid = uuid.uuid4().hex
    emit('queue_create', qid=q._benchmark_audit_qid)
    return q
multiprocessing.Queue = audited_queue

_orig_put = multiprocessing.queues.Queue.put
_orig_get = multiprocessing.queues.Queue.get

def qid(q):
    return getattr(q, '_benchmark_audit_qid', 'fallback-' + str(id(q)))

def audited_put(self, *args, **kwargs):
    emit('queue_put', qid=qid(self))
    return _orig_put(self, *args, **kwargs)

def audited_get(self, *args, **kwargs):
    emit('queue_get', qid=qid(self))
    return _orig_get(self, *args, **kwargs)

multiprocessing.queues.Queue.put = audited_put
multiprocessing.queues.Queue.get = audited_get

_orig_tm_start = tracemalloc.start
_orig_tm_get = tracemalloc.get_traced_memory
_orig_tm_stop = tracemalloc.stop

def tm_start(*args, **kwargs):
    emit('tracemalloc_start')
    return _orig_tm_start(*args, **kwargs)

def tm_get(*args, **kwargs):
    value = _orig_tm_get(*args, **kwargs)
    emit('tracemalloc_get', current=value[0], peak=value[1])
    return value

def tm_stop(*args, **kwargs):
    emit('tracemalloc_stop')
    return _orig_tm_stop(*args, **kwargs)

tracemalloc.start = tm_start
tracemalloc.get_traced_memory = tm_get
tracemalloc.stop = tm_stop
PY

if [ ! -f /home/user/benchmark_processor.py ]; then
    RUN_STATUS=127
else
    PYTHONPATH="$SITE_DIR" BENCHMARK_AUDIT_LOG="$AUDIT" timeout 30s python3 /home/user/benchmark_processor.py >/tmp/benchmark_stdout.txt 2>/tmp/benchmark_stderr.txt || RUN_STATUS=$?
fi
export RUN_STATUS AUDIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
from collections import Counter, defaultdict
import pytest

SCRIPT = '/home/user/benchmark_processor.py'
REPORT = '/home/user/qa_report.json'
DATA_FILE = '/home/user/test_data.txt'
AUDIT = os.environ.get('AUDIT', '/tmp/benchmark_audit.jsonl')

def is_prime(n):
    if n < 2:
        return False
    for i in range(2, int(n ** 0.5) + 1):
        if n % i == 0:
            return False
    return True

def expected_report_values():
    assert os.path.exists(DATA_FILE), f"{DATA_FILE} is missing."
    with open(DATA_FILE, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
    primes = []
    for line in lines:
        value = eval(line)
        if is_prime(value):
            primes.append(value)
    primes.sort(reverse=True)
    return lines, len(primes), primes[:5]

def load_report():
    with open(REPORT, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail('The file /home/user/qa_report.json does not contain valid JSON.')

def load_events():
    assert os.path.isfile(AUDIT), 'The processor did not produce a runtime audit log.'
    events = []
    with open(AUDIT, 'r') as f:
        for line in f:
            if line.strip():
                events.append(json.loads(line))
    return events

def test_processor_exists_and_executed():
    assert os.path.exists(SCRIPT), 'The file /home/user/benchmark_processor.py does not exist.'
    assert os.path.isfile(SCRIPT), '/home/user/benchmark_processor.py is not a regular file.'
    with open(SCRIPT, 'r') as f:
        ast.parse(f.read(), filename=SCRIPT)
    assert int(os.environ.get('RUN_STATUS', '1')) == 0, 'benchmark_processor.py did not run successfully.'

def test_qa_report_exists():
    """Check that the qa_report.json file was created."""
    assert os.path.exists(REPORT), 'The file /home/user/qa_report.json does not exist.'
    assert os.path.isfile(REPORT), '/home/user/qa_report.json is not a file.'

def test_qa_report_content():
    """Check the content of qa_report.json against expected values derived from test_data.txt."""
    _, expected_prime_count, expected_top_5 = expected_report_values()
    data = load_report()

    assert set(data) == {'peak_memory_bytes', 'prime_count', 'top_5_primes'}, 'qa_report.json must have exactly the required three fields.'
    assert 'peak_memory_bytes' in data, "Missing 'peak_memory_bytes' in qa_report.json"
    assert isinstance(data['peak_memory_bytes'], int) and not isinstance(data['peak_memory_bytes'], bool), "'peak_memory_bytes' must be an integer"
    assert data['peak_memory_bytes'] > 0, "'peak_memory_bytes' should be a positive integer"

    assert 'prime_count' in data, "Missing 'prime_count' in qa_report.json"
    assert data['prime_count'] == expected_prime_count, f"Expected prime_count {expected_prime_count}, got {data['prime_count']}"

    assert 'top_5_primes' in data, "Missing 'top_5_primes' in qa_report.json"
    assert data['top_5_primes'] == expected_top_5, f"Expected top_5_primes {expected_top_5}, got {data['top_5_primes']}"

def test_runtime_uses_producer_four_process_consumers_and_queues():
    lines, _, _ = expected_report_values()
    events = load_events()

    started = [e for e in events if e['kind'] == 'process_started']
    child_pids = {e.get('child_pid') for e in started if isinstance(e.get('child_pid'), int)}
    assert len(child_pids) in (4, 5), 'Expected four consumer processes and at most one separate producer process.'

    parent_pids = {e['pid'] for e in started}
    assert len(parent_pids) == 1, 'All worker processes must be orchestrated by one main process.'
    main_pid = next(iter(parent_pids))

    gets = defaultdict(Counter)
    puts = defaultdict(Counter)
    for event in events:
        if event['kind'] == 'queue_get':
            gets[event['qid']][event['pid']] += 1
        elif event['kind'] == 'queue_put':
            puts[event['qid']][event['pid']] += 1

    job_candidates = []
    for queue_id in set(gets) | set(puts):
        consumer_pids = {pid for pid, count in gets[queue_id].items() if pid in child_pids and count > 0}
        producer_count = sum(count for pid, count in puts[queue_id].items() if pid not in consumer_pids)
        if len(consumer_pids) == 4 and producer_count >= len(lines):
            job_candidates.append((queue_id, consumer_pids))
    assert job_candidates, 'No jobs Queue was used by one producer and exactly four Process consumers.'

    valid_pair = None
    for jobs_qid, consumers in job_candidates:
        for results_qid in set(gets) | set(puts):
            if results_qid == jobs_qid:
                continue
            result_puts = sum(puts[results_qid][pid] for pid in consumers)
            main_gets = gets[results_qid][main_pid]
            if result_puts >= len(lines) and main_gets >= len(lines):
                valid_pair = (jobs_qid, results_qid, consumers, main_pid)
                break
        if valid_pair:
            break
    assert valid_pair is not None, 'The four consumers did not send all expression results through a results Queue to the main process.'

def test_tracemalloc_covers_orchestration_and_reported_peak():
    data = load_report()
    events = load_events()
    started = [e for e in events if e['kind'] == 'process_started']
    assert started, 'No multiprocessing.Process instances were started.'
    main_pid = started[0]['pid']
    main_events = [e for e in events if e['pid'] == main_pid]

    starts = [e for e in main_events if e['kind'] == 'tracemalloc_start']
    gets = [e for e in main_events if e['kind'] == 'tracemalloc_get']
    stops = [e for e in main_events if e['kind'] == 'tracemalloc_stop']
    assert starts, 'tracemalloc.start() was not called in the main process.'
    assert gets, 'tracemalloc.get_traced_memory() was not called in the main process.'
    assert stops, 'tracemalloc.stop() was not called in the main process.'

    start_time = min(e['time'] for e in starts)
    stop_time = max(e['time'] for e in stops)
    process_start_times = [e['time'] for e in main_events if e['kind'] == 'process_start']
    assert process_start_times and start_time < min(process_start_times), 'Memory tracing must start before the producer/consumer processes start.'

    main_result_gets = [e['time'] for e in main_events if e['kind'] == 'queue_get']
    assert main_result_gets and stop_time > max(main_result_gets), 'Memory tracing must stop only after the main process has collected all results.'

    matching = [e for e in gets if e.get('peak') == data['peak_memory_bytes'] and start_time < e['time'] < stop_time]
    assert matching, "peak_memory_bytes was not the peak returned by tracemalloc.get_traced_memory()."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
