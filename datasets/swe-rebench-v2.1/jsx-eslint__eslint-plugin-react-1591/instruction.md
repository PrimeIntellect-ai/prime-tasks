(react/jsx-key) still warns when wrapping with React.Children.toArray
The (react/jsx-key) rule seems to still warn for instances wrapped with the `React.Children.toArray` utility.

This seems to be a bug since React no longer warns about missing keys when wrapping and considers it valid (the toArray utility provides keys to each item automatically)

```javascript

// React and lint rule both warn
{
  things.map(item => <Thing {...item} />)
}

// lint rule warns but React considers this to be valid
{
  React.Children.toArray(
    things.map(item => <Thing {...item} />)
  )
}
```

### Suggested Solution:

The rule accounts for instances wrapped with `React.Children.toArray` correctly and does not warn.

**_Edit:_**
I incorrectly described this as the no-array-index (as key) rule from this eslint plugin, but it is actually: `[eslint] Missing "key" prop for element in iterator (react/jsx-key)`. Updated the body of the issue plus the title to reflect the correct rule.
