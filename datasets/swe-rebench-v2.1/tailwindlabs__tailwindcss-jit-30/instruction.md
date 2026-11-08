@font-face declarations breaking
Using the new @tailwindcss/jit compiler seems to break font-face declarations added to base styles.

Using code like this in your CSS entry point:
```
@layer base {
  @font-face {
    font-family: "test";
    src: url("/fonts/test.woff2") format("woff2");
    font-weight: 400;
    font-style: normal;
    font-display: swap;
  }
  @font-face {
    font-family: "test";
    src: url("/fonts/test-italic.woff2") format("woff2");
    font-weight: 400;
    font-style: italic;
    font-display: swap;
  }
}
```

Results in the following CSS during dev and build:
```
  @font-face {
    font-family: "test";
    src: url("/fonts/test.woff2") format("woff2");
    font-weight: 400;
    font-style: normal;
    font-display: swap;
    font-family: "test";
    src: url("/fonts/test-italic.woff2") format("woff2");
    font-weight: 400;
    font-style: italic;
    font-display: swap;
  }
```

Without JIT, the font-face declarations are compiled to individual declarations and work as usual.

Versions:
```
"@tailwindcss/jit": "^0.1.0",
"tailwindcss": "^2.0.3",
```
