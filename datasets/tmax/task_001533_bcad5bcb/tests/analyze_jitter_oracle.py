import sys
import numpy as np
import fast_stat_profiler

def main():
    lines = sys.stdin.read().strip().split('\n')
    if not lines or lines == ['']:
        return
    latencies = []
    for line in lines:
        try:
            parts = line.split(',')
            latencies.append(float(parts[1]))
        except:
            pass

    cleaned = fast_stat_profiler.clean_latency(latencies)
    fft_vals = np.fft.fft(cleaned)
    mags = np.abs(fft_vals)

    # Ignore DC component
    mags[0] = -1.0

    # Sort by magnitude descending, then index ascending
    # We can do this by creating a list of tuples
    mag_idx = [(-mags[i], i) for i in range(1, len(mags))]
    mag_idx.sort()

    for i in range(min(3, len(mag_idx))):
        mag = -mag_idx[i][0]
        idx = mag_idx[i][1]
        print(f"Idx: {idx}, Mag: {mag:.4f}")

if __name__ == "__main__":
    main()
