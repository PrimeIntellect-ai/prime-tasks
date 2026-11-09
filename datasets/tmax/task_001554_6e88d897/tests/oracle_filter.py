#!/usr/bin/env python3
import sys

def main():
    if len(sys.argv) < 2:
        return
    seq = sys.argv[1].upper()
    mapping = {'A': 2, 'C': -1, 'G': 3, 'T': -2}
    kernel = [1, -1, 2]

    nums = [mapping.get(c, 0) for c in seq]

    if len(nums) < len(kernel):
        print("")
        return

    out = []
    for i in range(len(nums) - len(kernel) + 1):
        val = (nums[i] * kernel[0] + 
               nums[i+1] * kernel[1] + 
               nums[i+2] * kernel[2])
        out.append(str(val))

    print(" ".join(out))

if __name__ == "__main__":
    main()
