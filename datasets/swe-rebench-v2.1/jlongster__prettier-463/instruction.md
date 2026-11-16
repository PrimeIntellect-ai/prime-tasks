Inserting space before comma in objects with non-trivial value
It seems when I have an object with a key pointing to a non-trivial value and am using trailing commas, prettier inserts a space before the comma. Since it does not insert a space before commas normally, I assume this is a bug. FWIW, I couldn't reproduce on the live editor linked from this github repo (which appears to be based on the last release), so I'm assuming this is a recent problem introduced in master.

I created a failing spec here: https://github.com/joefiorini/prettier/blob/space-before-trailing-comma/tests/trailing_comma/object.js. I took a stab at making it pass, but don't have time atm to wrap my head around how it all works.

### Additional contract requirements

- The spurious space is not limited to trailing commas: it also appears before commas that separate object properties. The fix must remove the extra space before such commas as well. For example, `const a = { b: a === a, c: 1 };` must be formatted as `const a = { b: a === a, c: 1 };` (no space before the comma), not `const a = { b: a === a , c: 1 };`.
