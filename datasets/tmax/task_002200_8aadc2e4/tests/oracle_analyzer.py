import sys

def custom_sort(arr):
    if len(arr) <= 1:
        return arr
    pivot = arr[len(arr) // 2]
    left = [x for x in arr if x < pivot]
    middle = [x for x in arr if x == pivot]
    right = [x for x in arr if x > pivot]
    return custom_sort(left) + middle + custom_sort(right)

def process(arr):
    arr = custom_sort(arr)
    for i in range(len(arr)):
        current = arr[i]
        previous = current + 1.0
        val = current
        while abs(val - previous) > 1e-6:
            previous = val
            val = val * 0.9 + 0.05
        arr[i] = val
    return arr

if __name__ == "__main__":
    input_data = sys.stdin.read().strip()
    if not input_data:
        print("")
        sys.exit(0)
    arr = [float(x) for x in input_data.split(",")]
    res = process(arr)
    print(",".join(f"{x:.6f}" for x in res))
