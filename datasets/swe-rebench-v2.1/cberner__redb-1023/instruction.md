Allow freeing uncommitted pages in Durability::None transactions
Durability::None transactions should be able to free pages from previous Durability::None transactions. This can be implemented by [HIDDEN], rather than placing them into the freed tree

### Additional contract requirements

- In the free-page cleanup sequence with each durability mode (`Immediate`, `Eventual`, and `None`), after an extra commit to finalize cleanup, the next write transaction's `allocated_pages()` count must equal the baseline count recorded before the sequence's page allocations. When a live read transaction spans multiple `Durability::None` commits that update the same entry, and that entry is subsequently removed and cleanup is committed, the resulting `allocated_pages()` count must be at most `allocated_pages * 2 + 2`, where `allocated_pages` is the baseline recorded before those non-durable commits.
