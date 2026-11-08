#!/usr/bin/env python3
import sys

def main():
    max_retries = 3
    retries = 0
    expected_sequence = ["INIT", "BUILD", "LINK", "TEST", "DEPLOYED"]
    current_index = 0

    for line in sys.stdin:
        line = line.strip()
        if line == "VALIDATION_FAILED":
            retries += 1
            if retries > max_retries:
                print("RATE_LIMIT_EXCEEDED")
                sys.exit(1)
        elif line.startswith("STATE: "):
            state = line.split("STATE: ")[1].strip()
            if current_index < len(expected_sequence) and state == expected_sequence[current_index]:
                current_index += 1
                if current_index == len(expected_sequence):
                    print("SUCCESS")
                    sys.exit(0)
            else:
                print("LINKING_ERROR")
                sys.exit(1)

if __name__ == "__main__":
    main()
