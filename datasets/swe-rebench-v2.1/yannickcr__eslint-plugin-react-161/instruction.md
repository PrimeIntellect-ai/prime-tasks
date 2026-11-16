Rule proposal: Warn on duplicate props
When you're in strict-mode you get warnings when you have duplicate properties in an object, a similiar warning for props on React components would be nice.

```javascript
return (
   <Mycomponent className={classes}
                            onClick={this.handleClick}
                            someOtherProp={stuff}
                            onClick={this.onClick} /> // Duplicate prop, should produce an ESLint error
);
```

### Additional contract requirements

- The rule is named `jsx-no-duplicate-props` and is available as a rule module at `lib/rules/jsx-no-duplicate-props`.
- The rule accepts an optional configuration object as its first option, with a boolean `ignoreCase` property. When `ignoreCase` is `true`, prop names are compared case-insensitively, so two props whose names differ only in letter case count as duplicates.
- Each duplicated prop produces its own reported error, so an element with two separate duplicated props reports two errors.
