bug: nested grouping ((group)) results in incorrect url
### What version of HonoX are you using?

0.1.42

### What steps can reproduce the bug?

Create the following routes:
```
...
routes
  (api)/
    api/
  (static)/
    (legal)/
      privacy-policy/
        index.tsx
```
Put any content in index.tsx.

### What is the expected behavior?

/privacy-policy is accessible via /privacy-policy in browser

### What do you see instead?

/privacy-policy is inaccessible, but //privacy-policy is (notice double slash)

### Additional information

It'd be really convenient if expected behavior is implemted. What do you think?

### Additional contract requirements

- A request to `//privacy-policy` must return HTTP 404.
