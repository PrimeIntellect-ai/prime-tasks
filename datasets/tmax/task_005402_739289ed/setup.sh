#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-numpy g++ libfftw3-dev
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Generate signal.txt using a short python snippet
    python3 -c "
import numpy as np
np.random.seed(42)
N = 1024
x = np.arange(N)
# True parameters in frequency domain: mean ~ 100 (which is 100/1024 Hz), amplitude ~ 50, var ~ 4.0
target_spectrum = 50.0 * np.exp(-((x - 100.0)**2) / (2 * 4.0)) + np.random.normal(0, 0.5, N)
# Inverse FFT to get the signal
signal = np.fft.irfft(target_spectrum[:513])
with open('signal.txt', 'w') as f:
    for val in signal:
        f.write(f'{val}\n')
"

    # Create the buggy C++ code
    cat << 'EOF' > /home/user/analyzer.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <fftw3.h>

using namespace std;

// Gaussian model
double gaussian(double x, double A, double mu, double sigma_sq) {
    return A * exp(-pow(x - mu, 2) / (2 * sigma_sq));
}

int main() {
    vector<double> signal;
    ifstream infile("signal.txt");
    double val;
    while (infile >> val) {
        signal.push_back(val);
    }
    infile.close();

    int N = signal.size();
    fftw_complex *out = (fftw_complex*) fftw_malloc(sizeof(fftw_complex) * (N/2 + 1));
    double *in = (double*) fftw_malloc(sizeof(double) * N);

    for(int i=0; i<N; i++) in[i] = signal[i];

    fftw_plan p = fftw_plan_dft_r2c_1d(N, in, out, FFTW_ESTIMATE);
    fftw_execute(p);

    vector<double> power(N/2 + 1);
    for(int i=0; i<=N/2; i++) {
        power[i] = sqrt(out[i][0]*out[i][0] + out[i][1]*out[i][1]);
    }

    // Optimization: Fit Gaussian to power spectrum
    // Initial guesses
    double A = 10.0;
    double mu = 90.0;
    double sigma_sq = 1.0;

    double lr = 0.01;
    double prev_loss = 1e9;

    for (int iter = 0; iter < 1000; iter++) {
        double grad_A = 0, grad_mu = 0, grad_sigma_sq = 0;
        double loss = 0;

        for (int x = 80; x < 120; x++) {
            double pred = gaussian(x, A, mu, sigma_sq);
            double err = pred - power[x];
            loss += err * err;

            // Gradients
            double exp_term = exp(-pow(x - mu, 2) / (2 * sigma_sq));
            grad_A += 2 * err * exp_term;
            grad_mu += 2 * err * A * exp_term * (x - mu) / sigma_sq;
            grad_sigma_sq += 2 * err * A * exp_term * pow(x - mu, 2) / (2 * sigma_sq * sigma_sq);
        }

        // BUGGY Step-size adaptation
        if (loss > prev_loss) {
            lr *= 1.2; // Diverges! Should be lr *= 0.5
        } else {
            lr *= 0.5; // Stagnates! Should be lr *= 1.05 or similar
        }

        A -= lr * grad_A;
        mu -= lr * grad_mu;
        sigma_sq -= lr * grad_sigma_sq;

        prev_loss = loss;
    }

    ofstream outfile("peak_params.csv");
    outfile << A << "," << mu << "," << sigma_sq << endl;
    outfile.close();

    fftw_destroy_plan(p);
    fftw_free(in); fftw_free(out);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
