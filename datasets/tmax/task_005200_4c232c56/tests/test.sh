#!/bin/bash
mkdir -p /logs/verifier
status=0

cat << 'TEST_EOF' > /root/test_final_state.py
import os
import csv
from datetime import datetime, timedelta

OUTPUT = '/home/user/output.csv'
TEMP = '/home/user/data/temperature.csv'
PRESSURE = '/home/user/data/pressure.csv'


def parse_time(value):
    return datetime.strptime(value, '%Y-%m-%dT%H:%M:%SZ')


def truncate_to_minute(value):
    return value.replace(second=0, microsecond=0)


def test_output_csv_exists():
    assert os.path.isfile(OUTPUT), '/home/user/output.csv is missing'


def test_output_csv_content():
    assert os.path.isfile(TEMP), f'{TEMP} is missing'
    assert os.path.isfile(PRESSURE), f'{PRESSURE} is missing'

    temps = []
    with open(TEMP, newline='') as handle:
        for row in csv.DictReader(handle):
            temps.append((parse_time(row['timestamp']), float(row['temperature'])))

    pressures = []
    with open(PRESSURE, newline='') as handle:
        for row in csv.DictReader(handle):
            pressures.append((parse_time(row['timestamp']), float(row['pressure'])))

    all_times = [t for t, _ in temps] + [t for t, _ in pressures]
    min_time = truncate_to_minute(min(all_times))
    max_time = truncate_to_minute(max(all_times))

    minutes = []
    current = min_time
    while current <= max_time:
        minutes.append(current)
        current += timedelta(minutes=1)

    agg_temps = {minute: [] for minute in minutes}
    for timestamp, value in temps:
        agg_temps[truncate_to_minute(timestamp)].append(value)

    agg_pressures = {minute: [] for minute in minutes}
    for timestamp, value in pressures:
        agg_pressures[truncate_to_minute(timestamp)].append(value)

    raw_temps = [
        sum(agg_temps[m]) / len(agg_temps[m]) if agg_temps[m] else None
        for m in minutes
    ]
    raw_pressures = [
        sum(agg_pressures[m]) / len(agg_pressures[m]) if agg_pressures[m] else None
        for m in minutes
    ]

    filled_temps = []
    last_temp = None
    for value in raw_temps:
        if value is not None:
            last_temp = value
        filled_temps.append(last_temp)

    interp_pressures = list(raw_pressures)
    for i in range(len(interp_pressures)):
        if interp_pressures[i] is None:
            prior_idx = i - 1
            while prior_idx >= 0 and interp_pressures[prior_idx] is None:
                prior_idx -= 1
            next_idx = i + 1
            while next_idx < len(interp_pressures) and raw_pressures[next_idx] is None:
                next_idx += 1
            if prior_idx >= 0 and next_idx < len(interp_pressures):
                prior_val = interp_pressures[prior_idx]
                next_val = raw_pressures[next_idx]
                steps = next_idx - prior_idx
                interp_pressures[i] = prior_val + (next_val - prior_val) * (i - prior_idx) / steps

    rolling_temps = []
    for i in range(len(filled_temps)):
        window = filled_temps[max(0, i - 4):i + 1]
        rolling_temps.append(sum(window) / len(window))

    expected_rows = []
    for i, minute in enumerate(minutes):
        expected_rows.append({
            'timestamp': minute.strftime('%Y-%m-%dT%H:%M:%SZ'),
            'temp_filled': f'{filled_temps[i]:.2f}',
            'pressure_interpolated': f'{interp_pressures[i]:.2f}',
            'temp_rolling_avg': f'{rolling_temps[i]:.2f}',
        })

    actual_rows = []
    with open(OUTPUT, newline='') as handle:
        reader = csv.DictReader(handle)
        assert reader.fieldnames == [
            'timestamp',
            'temp_filled',
            'pressure_interpolated',
            'temp_rolling_avg',
        ], 'CSV headers do not match expected exactly.'
        actual_rows.extend(reader)

    assert len(actual_rows) == len(expected_rows), (
        f'Expected {len(expected_rows)} rows, but got {len(actual_rows)}'
    )
    for i, expected in enumerate(expected_rows):
        for field in ('timestamp', 'temp_filled', 'pressure_interpolated', 'temp_rolling_avg'):
            assert actual_rows[i][field] == expected[field], (
                f'Row {i} {field} mismatch: expected {expected[field]}, '
                f'got {actual_rows[i][field]}'
            )
TEST_EOF

run_case() {
    rm -f /home/user/output.csv
    touch /home/user/output.csv || return 1
    chown user:user /home/user/output.csv || return 1
    chmod 600 /home/user/output.csv || return 1

    timeout 30s runuser -u user -- /root/process_etl_bin >/tmp/process.stdout 2>/tmp/process.stderr || return 1
    python3 -m pytest /root/test_final_state.py -x --tb=short || return 1
}

if [ ! -f /home/user/process.go ]; then
    echo '/home/user/process.go is missing' >&2
    status=1
elif ! (cd /home/user && timeout 60s go build -o /root/process_etl_bin process.go); then
    echo '/home/user/process.go did not compile as a Go program' >&2
    status=1
else
    # Protect verifier inputs while still allowing the unprivileged program to
    # create or replace output.csv in the sticky home directory.
    chown root:root /home/user /home/user/data /home/user/data/temperature.csv /home/user/data/pressure.csv || status=1
    chmod 1777 /home/user || status=1
    chmod 755 /home/user/data || status=1
    chmod 444 /home/user/data/temperature.csv /home/user/data/pressure.csv || status=1

    # Preserve the original behavioral check on the supplied fixtures.
    if [ "$status" -eq 0 ] && ! run_case; then
        status=1
    fi

    # Exercise the compiled artifact again on unpredictable inputs so a fixed
    # seven-row output cannot satisfy the verifier.
    if [ "$status" -eq 0 ]; then
        if ! python3 - << 'PY_EOF'
import secrets

base_temp = 15 + secrets.randbelow(16)
base_pressure = 950 + secrets.randbelow(81)

with open('/home/user/data/temperature.csv', 'w') as f:
    f.write('timestamp,temperature\n')
    f.write(f'2024-02-03T09:58:07Z,{base_temp}.00\n')
    f.write(f'2024-02-03T09:58:53Z,{base_temp + 2}.00\n')
    f.write(f'2024-02-03T10:00:21Z,{base_temp + 3}.00\n')
    f.write(f'2024-02-03T10:02:02Z,{base_temp + 6}.00\n')
    f.write(f'2024-02-03T10:02:49Z,{base_temp + 8}.00\n')
    f.write(f'2024-02-03T10:05:59Z,{base_temp + 10}.00\n')

with open('/home/user/data/pressure.csv', 'w') as f:
    f.write('timestamp,pressure\n')
    f.write(f'2024-02-03T09:58:41Z,{base_pressure}.00\n')
    f.write(f'2024-02-03T10:01:05Z,{base_pressure + 6}.00\n')
    f.write(f'2024-02-03T10:01:44Z,{base_pressure + 8}.00\n')
    f.write(f'2024-02-03T10:03:17Z,{base_pressure + 3}.00\n')
    f.write(f'2024-02-03T10:07:31Z,{base_pressure + 12}.00\n')
PY_EOF
        then
            status=1
        else
            chmod 444 /home/user/data/temperature.csv /home/user/data/pressure.csv
            if ! run_case; then
                status=1
            fi
        fi
    fi
fi

if [ "$status" -eq 0 ]; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
