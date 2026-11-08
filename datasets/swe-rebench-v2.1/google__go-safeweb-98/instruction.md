Prevent double-writing to the ResponseWriter
This is one of the most critical security features.

Double-writing should likely result in panic.

### Additional contract requirements

Every response-writing attempt after the first must panic, and it must not emit any part of a second response.
