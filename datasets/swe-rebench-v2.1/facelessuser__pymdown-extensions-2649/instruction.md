Compatibility issues with Highlighting Lines in Code blocks
### Description

I have a paragraph in my markdown text like this, and when I run it, it parses incorrectly, causing the rendered page to be completely misaligned, here's the source file: [TestOne.md](https://github.com/user-attachments/files/18033885/TestOne.md).

````
```javascript [4]
function hello(name) {
    let phrase = `Hello, ${name}!`;

    debugger;

    say(phrase);
}
```
````

<mark>It would be rendered like this:</mark>

<img width="719" alt="iShot_2024-12-06_14 32 12" src="https://github.com/user-attachments/assets/19f04566-4dd8-4eef-9d57-4e66ab1552d7">

---

<mark>This is the correct parsing in Typora：</mark>

<img width="986" alt="iShot_2024-12-06_14 32 36" src="https://github.com/user-attachments/assets/e8bf790c-3f25-47d1-87aa-5534864372f8">

<br />The reason is that the [4] after the token is not recognized, and it treats the [4] as the beginning of the code, which should normally be the next line.

I know this is not the canonical writeup for this project, but it could be designed so that ignore unrecognized markup when it is encountered, thus not affecting the parsing and rendering of later text.This writeup renders fine in other editors, such as Typora, Github and so on.

This writeup is from other project [revealjs](https://revealjs.com/code/), I compared, this design is much simpler, just need to set the number, don't need to remember the property name, and it also supports step-by-step highlights.

- If you agree with this design, you can consider adding support in subsequent updates;
- If other settings are involved and it is troublesome to modify, then forget it, but it needs to be designed to ignore the markup and not affect the analysis and rendering of the following text;

Here are some write-ups for comparison and reference:

<img width="966" alt="iShot_2024-12-05_12 40 08" src="https://github.com/user-attachments/assets/1aba0412-8041-4e47-b4eb-efb6cf3958a0">

### Minimal Reproduction

unnecessary

### Version(s) & System Info

unnecessary

### Additional contract requirements

- SuperFences gains a boolean configuration option named `relaxed_headers` (default `False`).
- When `relaxed_headers` is enabled, a fenced code block whose header contains unrecognized markup (for example ` ```javascript [4] `) is still processed as a code block: the unrecognized markup is ignored rather than being treated as code or causing the whole block to be abandoned. When the language token is recognized, the block is highlighted as that language.
- When `relaxed_headers` is not enabled, such headers continue to be treated as invalid, preserving the previous behavior.
