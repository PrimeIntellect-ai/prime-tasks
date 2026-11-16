.toHaveClass custom matcher
At risk of sounding like I want to bloat the set of custom matchers provided by this lib, I'd like to propose `.toHaveClass('dropdown-toggle')`. The `class` attribute in html is designed to have multiple classes encoded in it, and it's often nice to be able to reliably check if an element has a certain class while ignoring the rest of what's encoded in the `class` attribute value.

```javascript
// ...
// <button data-testid="delete-button" type="submit" class="btn btn-danger">
//   Delete item
// </button>
expect(getByTestId('delete-button')).toHaveClass('btn-danger')
```

Raising it as an issue first to see if it's considered useful for this lib, and also to discuss potential names:

- `toHaveClass`
- `toIncludeClass`
- `toContainClass`
- something else?

Or all of the above but ending with `*ClassName` instead of just `*Class`.
