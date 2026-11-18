import sys

def simulate(seed, num_steps, K=25):
    state = seed
    pos = 0
    for _ in range(num_steps):
        for _ in range(K):
            state = (1103515245 * state + 12345) % (2**31)
            pos += (state % 3) - 1
    print(pos)

if __name__ == "__main__":
    simulate(int(sys.argv[1]), int(sys.argv[2]))
