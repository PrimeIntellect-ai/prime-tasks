#!/usr/bin/env python3
import sys, requests, math, redis

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    text = sys.argv[1]

    # 1. Tokenize
    try:
        resp = requests.post("http://127.0.0.1:5000/tokenize", json={"text": text})
        tokens = resp.json().get("tokens", [])
    except Exception:
        print("0.0000")
        return

    if not tokens:
        print("0.0000")
        return

    # 2. Outlier Detection (CI)
    lengths = [len(t) for t in tokens]
    n = len(lengths)
    mean_len = sum(lengths) / n
    if n > 1:
        variance = sum((l - mean_len) ** 2 for l in lengths) / (n - 1)
        std_dev = math.sqrt(variance)
        moe = 1.96 * (std_dev / math.sqrt(n))
    else:
        moe = 0.0

    upper_bound = mean_len + moe
    if upper_bound > 12.0:
        print("-1.0000")
        return

    # 3. Bayesian Inference
    r = redis.Redis(host='127.0.0.1', port=6379, db=0, decode_responses=True)
    prior = r.get('prior_A')
    if prior is None:
        log_prob = -0.5
    else:
        log_prob = float(prior)

    for t in tokens:
        val = r.get(f"token_A:{t}")
        if val is None:
            log_prob += -5.0
        else:
            log_prob += float(val)

    # 4. Output
    print(f"{log_prob:.4f}")

if __name__ == "__main__":
    main()
