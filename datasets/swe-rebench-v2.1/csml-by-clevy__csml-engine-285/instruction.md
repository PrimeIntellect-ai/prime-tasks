forget memory
**Is your feature request related to a problem? Please describe.**
currently there is no easy way to delete client memories, the only option available is replacing by null
example: do var = null

**Describe the solution you'd like**
add a new keyword 'forget'

forget * // all memories
forget tutu // single memory
forget [tutu, tata, toto] // list of memories

### Additional contract requirements

- A `forget` instruction deletes the specified memories from the client's memory, so that after it runs the built-in `_memory` value no longer contains the forgotten memories.
