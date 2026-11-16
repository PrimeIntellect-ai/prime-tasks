[FORMATTING] Inline block comment has error
I using Postgresql support block comment.
**Input data**
/*
/* inline block comment */
*/

**Expected Output**

```sql
/*
/* inline block comment */
*/
```

**Actual Output**

```sql
/*
/* inline block comment */
* /
```

It has one space character in * and /

**Usage**

- How are you calling / using the library? YES
- What SQL language(s) does this apply to? SQL
- Which SQL Formatter version are you using? 10.0.0

### Additional contract requirements

- PostgreSQL and Transact-SQL support nested block comments: a block comment may itself contain further `/* ... */` block comments, and the whole nested construct is treated as a single comment. The closing `*/` delimiter of such a comment must be preserved exactly (it must not be split into `* /`).
- Other SQL dialects do not support nested block comments: for them a nested construct is not treated as a single comment.
- Provide a public class `NestedComment` in module `src/lexer/NestedComment.ts` with a mutable `lastIndex: number` property and a method `exec(input: string): string[] | null`. When `lastIndex` points at an opening `/*`, `exec` returns a one-element array containing the entire properly closed and correctly nested block comment, including its delimiters. It returns `null` when the input at `lastIndex` is not an opening `/*`, when the comment is not closed, or when the nesting is malformed.
- A tokenizer option `nestedBlockComments` (boolean, declared in `src/lexer/TokenizerOptions.ts`) enables nested block-comment matching when `true`; when omitted or `false`, block comments are matched with the simple non-nested block-comment regex.
