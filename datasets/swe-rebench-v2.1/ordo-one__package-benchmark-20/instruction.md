Detect and handle multiple identical Benchmark definitions
Easy to do mistake when copy/pasting benchmarks, we should fatalError() so it's not silently discarded as it currently is.
