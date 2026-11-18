import sys

def main():
    if len(sys.argv) != 4:
        sys.exit(1)

    v1 = float(sys.argv[1])
    v2 = float(sys.argv[2])
    v3 = float(sys.argv[3])

    # Diagonal matrix: [2.5, 0, 0], [0, -1.5, 0], [0, 0, 4.2]
    out1 = v1 * 2.5
    out2 = v2 * -1.5
    out3 = v3 * 4.2

    print(f"{out1:.4f} {out2:.4f} {out3:.4f}")

if __name__ == "__main__":
    main()
