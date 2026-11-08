False positive scss/operator-no-unspaced  Expected single space after "-"
Input:

```
@mixin test {
  @for $i from 0 through 10 {
    &:nth-child(#{$i + 1}) {
      top: #{$i * -10}px;
      transform: scale(#{(10 - $i) * 0.1}) !important;
    }
  }
}
```
Require:

```
@mixin test {
  @for $i from 0 through 10 {
    &:nth-child(#{$i + 1}) {
      top: #{$i * - 10}px;
      transform: scale(#{(10 - $i) * 0.1}) !important;
    }
  }
}
```
Expected (no errors):

```
@mixin test {
  @for $i from 0 through 10 {
    &:nth-child(#{$i + 1}) {
      top: #{$i * -10}px;
      transform: scale(#{(10 - $i) * 0.1}) !important;
    }
  }
}
```
