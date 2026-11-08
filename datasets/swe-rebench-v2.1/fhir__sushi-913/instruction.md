A code can be included muliple times in a Value Set
SUSHI allows easily detectable GIGO errors.... if you include the same code in a VS > 1 time, it comes out > 1 time.   An easy check for duplicate code/code-system would save ballot comments.

See https://fshschool.org/FSHOnline/#/share/3g9tIzO

The duplicate code ends in 008

### Additional contract requirements

- Within a ValueSet, include at most one occurrence of a concept with the same system, version, and code. A different system or version makes it a distinct concept; this includes the distinction between a version being absent and present.
- Retain nonduplicate concepts. When a repeated concept is suppressed, emit a warning that identifies the repeated code.
