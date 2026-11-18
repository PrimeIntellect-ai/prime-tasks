#!/usr/bin/env python3
import sys
import math

def main():
    data = sys.stdin.read().split()
    if not data:
        return
    nums = [float(x) for x in data]
    n = len(nums)
    if n < 2:
        return

    # KDE at x=0, h=1.25
    h = 1.25
    kde_sum = 0.0
    for x in nums:
        z = (0.0 - x) / h
        kde_sum += math.exp(-0.5 * z**2) / math.sqrt(2 * math.pi)
    kde = kde_sum / (n * h)

    # CI using normal approx
    mean = sum(nums) / n
    variance = sum((x - mean)**2 for x in nums) / (n - 1)
    std_dev = math.sqrt(variance)

    margin = 1.96 * std_dev / math.sqrt(n)
    ci_lower = mean - margin
    ci_upper = mean + margin

    print(f"{kde:.4f},{ci_lower:.4f},{ci_upper:.4f}")

if __name__ == "__main__":
    main()
