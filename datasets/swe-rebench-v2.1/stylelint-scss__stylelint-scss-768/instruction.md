`operator-no-unspaced` registring `*` as operator although it is used as a selector
Hi, this looks to me as a false positive:

SCSS code:
```scss
.element {
    @supports selector(:has(*)) {
        opacity: 0;
    }
}
```
stylelintrc config:
```json
{
  "plugins": [
    "stylelint-scss"
  ],
  "rules": {
    "scss/operator-no-unspaced": true
  }
}
```
Error:
```
2:26  ✖  Expected single space before "*"  scss/operator-no-unspaced
2:26  ✖  Expected single space after "*"   scss/operator-no-unspaced
```

Wrapping the `*` with space, to me seems unnecessary here and prettier would try to remove them.


reproduce issue via https://github.com/mbehzad/stylelint-scss-operator-no-unspaced-issue
