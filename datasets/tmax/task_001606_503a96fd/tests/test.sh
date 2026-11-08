#!/bin/bash
mkdir -p /logs/verifier

cat << 'ORACLE_EOF' > /tmp/compute_expected.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

static int cmp_double(const void *a, const void *b) {
    double x = *(const double *)a;
    double y = *(const double *)b;
    return (x > y) - (x < y);
}

static double lerp(double a, double b, double t) {
    return a + (b - a) * t;
}

int main(void) {
    FILE *wav = fopen("/app/anomaly_candidate.wav", "rb");
    if (!wav || fseek(wav, 44, SEEK_SET) != 0) return 2;

    double energy_sum_d = 0.0;
    float energy_sum_f = 0.0f;
    long crossings = 0, count = 0;
    int16_t previous = 0, sample;
    int have_previous = 0;

    while (fread(&sample, sizeof(sample), 1, wav) == 1) {
        float fs = (float)sample;
        float square = fs * fs;
        energy_sum_d += (double)square;
        energy_sum_f += square;
        if (have_previous && ((previous < 0 && sample >= 0) ||
                              (previous >= 0 && sample < 0))) {
            crossings++;
        }
        previous = sample;
        have_previous = 1;
        count++;
    }
    fclose(wav);
    if (count < 2) return 3;

    double candidate_energy_d = energy_sum_d / (double)count;
    float candidate_energy_f = energy_sum_f / (float)count;
    double candidate_zcr = (double)crossings / (double)(count - 1);

    FILE *csv = fopen("/app/baseline_metrics.csv", "r");
    if (!csv) return 4;
    size_t cap = 1024, n = 0;
    double *energy = malloc(cap * sizeof(double));
    double *zcr = malloc(cap * sizeof(double));
    if (!energy || !zcr) return 5;
    double e, z;
    while (fscanf(csv, " %lf,%lf", &e, &z) == 2) {
        if (n == cap) {
            cap *= 2;
            double *ne = realloc(energy, cap * sizeof(double));
            double *nz = realloc(zcr, cap * sizeof(double));
            if (!ne || !nz) return 6;
            energy = ne;
            zcr = nz;
        }
        energy[n] = e;
        zcr[n] = z;
        n++;
    }
    fclose(csv);
    if (n == 0) return 7;

    double *boot_e = malloc(10000 * sizeof(double));
    double *boot_z = malloc(10000 * sizeof(double));
    if (!boot_e || !boot_z) return 8;

    srand(42);
    for (int iteration = 0; iteration < 10000; iteration++) {
        double sum_e = 0.0, sum_z = 0.0;
        for (size_t j = 0; j < n; j++) {
            size_t index = (size_t)rand() % n;
            sum_e += energy[index];
            sum_z += zcr[index];
        }
        boot_e[iteration] = sum_e / (double)n;
        boot_z[iteration] = sum_z / (double)n;
    }
    qsort(boot_e, 10000, sizeof(double), cmp_double);
    qsort(boot_z, 10000, sizeof(double), cmp_double);

    /* Accept the standard nearest/lower choices and the common inclusive and
       exclusive linear percentile definitions. */
    double elo_inc = lerp(boot_e[249], boot_e[250], 0.975);
    double elo_exc = lerp(boot_e[249], boot_e[250], 0.025);
    double ehi_inc = lerp(boot_e[9749], boot_e[9750], 0.025);
    double ehi_exc = lerp(boot_e[9749], boot_e[9750], 0.975);
    double zlo_inc = lerp(boot_z[249], boot_z[250], 0.975);
    double zlo_exc = lerp(boot_z[249], boot_z[250], 0.025);
    double zhi_inc = lerp(boot_z[9749], boot_z[9750], 0.025);
    double zhi_exc = lerp(boot_z[9749], boot_z[9750], 0.975);

    int anomaly = candidate_energy_d < boot_e[250] ||
                  candidate_energy_d > boot_e[9750] ||
                  candidate_zcr < boot_z[250] ||
                  candidate_zcr > boot_z[9750];

    printf("CE %.2f %.2f\n", candidate_energy_d, (double)candidate_energy_f);
    printf("CZ %.4f\n", candidate_zcr);
    printf("ELO %.2f %.2f %.2f %.2f\n", boot_e[249], boot_e[250], elo_inc, elo_exc);
    printf("EHI %.2f %.2f %.2f %.2f\n", boot_e[9749], boot_e[9750], ehi_inc, ehi_exc);
    printf("ZLO %.4f %.4f %.4f %.4f\n", boot_z[249], boot_z[250], zlo_inc, zlo_exc);
    printf("ZHI %.4f %.4f %.4f %.4f\n", boot_z[9749], boot_z[9750], zhi_inc, zhi_exc);
    printf("ANOM %s\n", anomaly ? "true" : "false");

    free(energy); free(zcr); free(boot_e); free(boot_z);
    return 0;
}
ORACLE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import re
import socket
import pytest


def load_expected():
    result = {}
    with open('/tmp/expected.txt', encoding='ascii') as f:
        for line in f:
            parts = line.split()
            result[parts[0]] = parts[1:]
    return result


def request_report(fragmented=False):
    host = '127.0.0.1'
    port = 8585
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5.0)
        s.connect((host, port))
    except Exception as e:
        pytest.fail(f"Could not connect to {host}:{port}: {e}")

    try:
        if fragmented:
            s.sendall(b"GET_")
            s.sendall(b"REPORT\n")
        else:
            s.sendall(b"GET_REPORT\n")
        response = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            response += chunk
    except Exception as e:
        pytest.fail(f"Error communicating with service: {e}")
    finally:
        s.close()
    return response


def validate_response(response, expected):
    assert response, "Received empty response from service"
    try:
        text = response.decode('utf-8')
    except UnicodeDecodeError as e:
        pytest.fail(f"Response is not UTF-8: {e}")

    assert text.endswith('\n'), "JSON payload must be followed by a newline"

    num2 = r'(-?\d+\.\d{2})'
    num4 = r'(-?\d+\.\d{4})'
    pattern = re.compile(
        r'^\s*\{\s*'
        r'"candidate_energy"\s*:\s*' + num2 + r'\s*,\s*'
        r'"candidate_zcr"\s*:\s*' + num4 + r'\s*,\s*'
        r'"baseline_energy_ci"\s*:\s*\[\s*' + num2 + r'\s*,\s*' + num2 + r'\s*\]\s*,\s*'
        r'"baseline_zcr_ci"\s*:\s*\[\s*' + num4 + r'\s*,\s*' + num4 + r'\s*\]\s*,\s*'
        r'"is_anomaly"\s*:\s*(true|false)\s*\}\n$'
    )
    match = pattern.fullmatch(text)
    assert match, "Response does not use the required key order and fixed decimal formatting"

    try:
        data = json.loads(text.strip())
    except json.JSONDecodeError as e:
        pytest.fail(f"Response is not valid JSON: {e}\nResponse was: {response}")

    expected_keys = {
        "candidate_energy",
        "candidate_zcr",
        "baseline_energy_ci",
        "baseline_zcr_ci",
        "is_anomaly"
    }
    assert set(data.keys()) == expected_keys, f"JSON keys do not match expected. Got: {list(data.keys())}"
    assert isinstance(data["candidate_energy"], (int, float)), "candidate_energy must be a number"
    assert isinstance(data["candidate_zcr"], (int, float)), "candidate_zcr must be a number"
    assert isinstance(data["baseline_energy_ci"], list) and len(data["baseline_energy_ci"]) == 2, "baseline_energy_ci must be a list of 2 numbers"
    assert isinstance(data["baseline_zcr_ci"], list) and len(data["baseline_zcr_ci"]) == 2, "baseline_zcr_ci must be a list of 2 numbers"
    assert isinstance(data["is_anomaly"], bool), "is_anomaly must be a boolean"

    for value in [data['candidate_energy'], data['candidate_zcr'], *data['baseline_energy_ci'], *data['baseline_zcr_ci']]:
        assert isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value), "All metrics and interval endpoints must be finite numbers"

    candidate_energy, candidate_zcr, energy_lo, energy_hi, zcr_lo, zcr_hi, anomaly = match.groups()
    assert candidate_energy in set(expected['CE']), f"Incorrect candidate_energy: {candidate_energy}"
    assert candidate_zcr == expected['CZ'][0], f"Incorrect candidate_zcr: {candidate_zcr}"
    assert energy_lo in set(expected['ELO']), f"Incorrect baseline energy lower percentile: {energy_lo}"
    assert energy_hi in set(expected['EHI']), f"Incorrect baseline energy upper percentile: {energy_hi}"
    assert zcr_lo in set(expected['ZLO']), f"Incorrect baseline ZCR lower percentile: {zcr_lo}"
    assert zcr_hi in set(expected['ZHI']), f"Incorrect baseline ZCR upper percentile: {zcr_hi}"
    assert anomaly == expected['ANOM'][0], f"Incorrect is_anomaly value: {anomaly}"
    assert data['baseline_energy_ci'][0] <= data['baseline_energy_ci'][1]
    assert data['baseline_zcr_ci'][0] <= data['baseline_zcr_ci'][1]


def test_service_response():
    expected = load_expected()
    validate_response(request_report(False), expected)
    # The service must remain available, and an exact request may arrive in
    # multiple TCP segments.
    validate_response(request_report(True), expected)
TEST_EOF

ok=1
gcc -O2 -std=c11 /tmp/compute_expected.c -o /tmp/compute_expected || ok=0
if [ "$ok" -eq 1 ]; then
    /tmp/compute_expected > /tmp/expected.txt || ok=0
fi
if [ "$ok" -eq 1 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
