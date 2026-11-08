New Rule: no-important
### Rule details

Flag the use of !important

### What type of rule is this?

Warns about a potential problem

### Example code

```css
.really-red {
    color: red !important;
}
```

### Participation

- [x] I am willing to submit a pull request to implement this rule.

### Additional comments

Needing `!important` indicates there may be a larger underlying issue.
