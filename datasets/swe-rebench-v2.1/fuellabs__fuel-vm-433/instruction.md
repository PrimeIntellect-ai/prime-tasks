Bitshift operations incorrectly panic on inputs that don't fit into u32
Using SLL or SRL operations with a shift value that doesn't fit in u32 results in a transaction-level panic, but that hasn't been documented. The operation should simply return zero, just like with u32::MAX.
