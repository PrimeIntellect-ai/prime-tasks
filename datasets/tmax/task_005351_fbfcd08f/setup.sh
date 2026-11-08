#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc time
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/compute_jsd.c
#include <stdio.h>
#include <math.h>

double P(double x) {
    return exp(-x*x);
}

double Q(double x) {
    return exp(-(x-1.0)*(x-1.0));
}

int main() {
    long long N = 50000000;
    double a = -10.0;
    double b = 10.0;
    double dx = (b - a) / N;

    double sum_P = 0.5 * (P(a) + P(b));
    double sum_Q = 0.5 * (Q(a) + Q(b));

    for(long long i = 1; i < N; i++) {
        double x = a + i * dx;
        sum_P += P(x);
        sum_Q += Q(x);
    }

    sum_P *= dx;
    sum_Q *= dx;

    double sum_JSD = 0.0;
    for(long long i = 1; i < N; i++) {
        double x = a + i * dx;
        double p = P(x) / sum_P;
        double q = Q(x) / sum_Q;
        double m = 0.5 * (p + q);
        if (p > 0) sum_JSD += 0.5 * p * log(p / m);
        if (q > 0) sum_JSD += 0.5 * q * log(q / m);
    }

    double p_a = P(a)/sum_P, q_a = Q(a)/sum_Q, m_a = 0.5*(p_a+q_a);
    double p_b = P(b)/sum_P, q_b = Q(b)/sum_Q, m_b = 0.5*(p_b+q_b);
    double end_JSD = 0.0;
    if (p_a > 0) end_JSD += 0.5 * p_a * log(p_a / m_a);
    if (q_a > 0) end_JSD += 0.5 * q_a * log(q_a / m_a);
    if (p_b > 0) end_JSD += 0.5 * p_b * log(p_b / m_b);
    if (q_b > 0) end_JSD += 0.5 * q_b * log(q_b / m_b);

    sum_JSD += 0.5 * end_JSD;
    sum_JSD *= dx;

    printf("%.6f\n", sum_JSD);
    return 0;
}
EOF

    chmod -R 777 /home/user
