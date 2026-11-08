#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import pytest


def test_validation_log():
    log_path = '/home/user/validation.log'
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."

    with open(log_path, 'r') as f:
        content = f.read().strip()

    match = re.match(r'^MAE:\s*([0-9]*\.?[0-9]+)$', content)
    assert match is not None, f"Log file content '{content}' does not match expected format 'MAE: <value>'."

    mae = float(match.group(1))
    assert 0.0 <= mae < 0.1, f"MAE value {mae} is not within the expected range [0.0, 0.1)."


def test_hdf5_data():
    h5_path = '/home/user/benchmark_data.h5'
    assert os.path.exists(h5_path), f"HDF5 file {h5_path} does not exist."

    try:
        import h5py
        import numpy as np
    except ImportError:
        pytest.fail("Required libraries h5py and numpy are not installed.")

    try:
        with h5py.File(h5_path, 'r') as f:
            assert 'signals' in f, "Dataset 'signals' not found in HDF5 file."
            assert 'peak_frequencies' in f, "Dataset 'peak_frequencies' not found in HDF5 file."

            signals = f['signals']
            peaks = f['peak_frequencies']

            assert signals.shape == (1000, 10000), f"Expected signals shape (1000, 10000), got {signals.shape}"
            assert peaks.shape == (1000,), f"Expected peak_frequencies shape (1000,), got {peaks.shape}"

            # Preserve the original deterministic checks.
            np.random.seed(42)
            indices_to_check = np.random.choice(1000, size=10, replace=False)
            freqs = np.fft.rfftfreq(10000, d=1/1000)

            for idx in indices_to_check:
                row = signals[idx]
                fft_mag = np.abs(np.fft.rfft(row))
                expected_peak = freqs[np.argmax(fft_mag)]
                actual_peak = peaks[idx]

                assert np.isclose(actual_peak, expected_peak, atol=0.01), \
                    f"Row {idx}: expected peak {expected_peak}, got {actual_peak}"

    except OSError:
        pytest.fail(f"File {h5_path} is not a valid HDF5 file.")


def test_full_workload_semantics_and_validation():
    import h5py
    import numpy as np

    h5_path = '/home/user/benchmark_data.h5'
    with h5py.File(h5_path, 'r') as f:
        # The instruction requires exactly two root-level datasets.
        assert set(f.keys()) == {'signals', 'peak_frequencies'}, \
            f"Expected exactly two root entries, got {list(f.keys())}"
        assert isinstance(f['signals'], h5py.Dataset)
        assert isinstance(f['peak_frequencies'], h5py.Dataset)

        signals_ds = f['signals']
        peaks = np.asarray(f['peak_frequencies'][...], dtype=np.float64)
        assert np.issubdtype(signals_ds.dtype, np.number) and signals_ds.dtype != np.bool_
        assert np.issubdtype(f['peak_frequencies'].dtype, np.number) and f['peak_frequencies'].dtype != np.bool_
        assert np.all(np.isfinite(peaks)), "Peak frequencies contain NaN or infinity."

        n = 1000
        m = 10000
        fs = 1000.0
        segment_len = 1000
        segment_centers = (np.arange(10, dtype=np.float64) + 0.5)
        centered_segments = segment_centers - segment_centers.mean()
        segment_denominator = np.sum(centered_segments ** 2)
        t = np.arange(m, dtype=np.float64) / fs
        fft_freqs = np.fft.rfftfreq(m, d=1.0/fs)

        inferred_f0 = np.empty(n, dtype=np.float64)
        amplitudes = np.empty(n, dtype=np.float64)
        row_means = np.empty(n, dtype=np.float64)
        row_stds = np.empty(n, dtype=np.float64)

        total_count = 0
        raw1 = raw2 = raw3 = raw4 = 0.0
        lag_sum = 0.0
        lag_count = 0
        cross_sum = 0.0
        cross_count = 0
        previous_residual = None

        chunk_size = 25
        for start in range(0, n, chunk_size):
            stop = min(n, start + chunk_size)
            rows = np.asarray(signals_ds[start:stop], dtype=np.float64)
            assert np.all(np.isfinite(rows)), "Signals contain NaN or infinity."

            # Recompute the positive-frequency FFT peak for every signal.
            magnitudes = np.abs(np.fft.rfft(rows, axis=1))
            peak_indices = np.argmax(magnitudes[:, 1:], axis=1) + 1
            expected_peaks = fft_freqs[peak_indices]
            assert np.allclose(peaks[start:stop], expected_peaks, rtol=0, atol=1e-6), \
                f"Stored peaks do not match FFT peaks for rows {start}:{stop}."

            # Infer each continuous fundamental independently of the submitted log.
            # At the stored 0.1-Hz bin, phase progression across ten 1-second
            # blocks gives the sub-bin frequency offset.
            demod = np.exp(-2j * np.pi * peaks[start:stop, None] * t[None, :])
            block_values = (rows * demod).reshape(stop-start, 10, segment_len).sum(axis=2)
            block_phase = np.unwrap(np.angle(block_values), axis=1)
            phase_slopes = np.sum(block_phase * centered_segments[None, :], axis=1) / segment_denominator
            f0 = peaks[start:stop] + phase_slopes / (2.0 * np.pi)
            inferred_f0[start:stop] = f0

            # Fit the required unit sinusoid and inspect the residual as noise.
            angle = 2.0 * np.pi * f0[:, None] * t[None, :]
            sin_x = np.sin(angle)
            cos_x = np.cos(angle)
            ss = np.sum(sin_x * sin_x, axis=1)
            cc = np.sum(cos_x * cos_x, axis=1)
            sc = np.sum(sin_x * cos_x, axis=1)
            ys = np.sum(rows * sin_x, axis=1)
            yc = np.sum(rows * cos_x, axis=1)
            determinant = ss * cc - sc * sc
            a = (ys * cc - yc * sc) / determinant
            b = (yc * ss - ys * sc) / determinant
            amplitudes[start:stop] = np.sqrt(a*a + b*b)
            residual = rows - a[:, None] * sin_x - b[:, None] * cos_x

            row_means[start:stop] = residual.mean(axis=1)
            row_stds[start:stop] = residual.std(axis=1)
            flat = residual.ravel()
            total_count += flat.size
            raw1 += float(np.sum(flat))
            raw2 += float(np.sum(flat ** 2))
            raw3 += float(np.sum(flat ** 3))
            raw4 += float(np.sum(flat ** 4))
            lag_sum += float(np.sum(residual[:, :-1] * residual[:, 1:]))
            lag_count += residual.shape[0] * (m - 1)
            cross_sum += float(np.sum(residual[1:] * residual[:-1]))
            cross_count += max(0, residual.shape[0] - 1) * m
            if previous_residual is not None:
                cross_sum += float(np.sum(previous_residual * residual[0]))
                cross_count += m
            previous_residual = residual[-1].copy()

    # Uniform fundamentals in the requested range, tested with generous bounds
    # so ordinary Monte Carlo variation is accepted.
    assert np.all((peaks >= 50.0) & (peaks <= 150.0)), \
        "FFT peaks are not in the requested fundamental-frequency range."
    assert np.all((inferred_f0 >= 49.9) & (inferred_f0 <= 150.1)), \
        "Inferred fundamentals are inconsistent with Uniform(50, 150)."
    assert abs(float(np.mean(inferred_f0)) - 100.0) < 4.0, \
        "Fundamental-frequency mean is inconsistent with Uniform(50, 150)."
    histogram, _ = np.histogram(inferred_f0, bins=10, range=(50.0, 150.0))
    assert histogram.sum() >= 995, "Too many inferred fundamentals fall outside the requested range."
    expected = histogram.sum() / 10.0
    chi_square = float(np.sum((histogram - expected) ** 2 / expected))
    assert chi_square < 35.0, "Fundamental frequencies are not plausibly uniform."

    # The fitted sinusoidal component must have amplitude one.
    assert 0.95 < float(np.mean(amplitudes)) < 1.05, \
        "Mean fitted sinusoid amplitude is inconsistent with amplitude 1."
    assert np.all((amplitudes > 0.80) & (amplitudes < 1.20)), \
        "One or more rows lack the required unit-amplitude sinusoid."

    # Validate mean-zero, standard-deviation-two Gaussian white noise and
    # independence across both samples and signals.
    mean = raw1 / total_count
    e2 = raw2 / total_count
    e3 = raw3 / total_count
    e4 = raw4 / total_count
    variance = e2 - mean * mean
    std = variance ** 0.5
    central3 = e3 - 3.0 * mean * e2 + 2.0 * mean ** 3
    central4 = e4 - 4.0 * mean * e3 + 6.0 * mean * mean * e2 - 3.0 * mean ** 4
    skewness = central3 / (std ** 3)
    kurtosis = central4 / (variance ** 2)
    lag_corr = (lag_sum / lag_count - mean * mean) / variance
    cross_corr = (cross_sum / cross_count - mean * mean) / variance

    assert abs(mean) < 0.03, f"Noise mean {mean} is inconsistent with 0."
    assert 1.95 < std < 2.05, f"Noise standard deviation {std} is inconsistent with 2."
    assert abs(skewness) < 0.08, f"Noise skewness {skewness} is not Gaussian-like."
    assert 2.90 < kurtosis < 3.10, f"Noise kurtosis {kurtosis} is not Gaussian-like."
    assert abs(lag_corr) < 0.01, f"Noise is not temporally white (lag correlation {lag_corr})."
    assert abs(cross_corr) < 0.01, f"Signals are not independent (cross correlation {cross_corr})."
    assert np.all(np.abs(row_means) < 0.10), "Some rows do not have mean-zero noise."
    assert np.all((row_stds > 1.85) & (row_stds < 2.15)), \
        "Some rows do not have noise standard deviation 2."

    # Recompute the requested MAE from fundamentals inferred from the generated
    # waveforms rather than trusting the submitted log.
    recomputed_mae = float(np.mean(np.abs(inferred_f0 - peaks)))
    with open('/home/user/validation.log', 'r') as log_file:
        match = re.fullmatch(r'MAE:\s*([0-9]*\.?[0-9]+)\n?', log_file.read())
    assert match is not None, "validation.log must contain exactly one MAE line."
    logged_mae = float(match.group(1))
    assert abs(logged_mae - recomputed_mae) < 0.004, \
        f"Logged MAE {logged_mae} does not match waveform-derived MAE {recomputed_mae}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
