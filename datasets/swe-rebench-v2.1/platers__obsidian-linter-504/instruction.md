Bug: "Capitalize headings" incorrectly capitalizes
## Describe the Bug

"Capitalize headings—first letter" rule is perhaps a bit too literal. It will capitalize the first letter even if it preceded by several other characters. This is usually not desirable.

## How to Reproduce

### Input

`### 1.0.0-b.4`

### Expected output

`### 1.0.0-b.4`

### Actual output

`### 1.0.0-B.4`

## Device

- [ ] Desktop
- [x] Mobile

### Additional contract requirements

- With the `First letter` style, `# 1.0-b this is a heading` must become `# 1.0-b This is a heading`.
