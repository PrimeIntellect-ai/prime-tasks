Prefer using native `getBy*` selectors
I've been going through our fairly large suite of Playwright tests and I noticed a common pattern that I think would be great to correct. If I have some time, I will try to contribute a rule for this.

The issue is that developers write a test like `expect(page.locator('[aria-label="View more"]'))` which works great until the element is updated to use `aria-labelledby` for labeling, instead of explicit `aria-label` attributes. From a semantic perspective this is equivalent, but it breaks the Playwright test. We should encourage people to use `getByLabel` instead in the first place to prevent this from breaking. It is easier to read, easier to maintain, and encourages an accessibility-first focus.

Examples:

```ts
// Incorrect:
page.locator('[aria-label="View more"]')
// Correct:
page.getByLabel('View more')
```

```ts
// Incorrect:
page.locator('[role="button"]')
// Correct:
page.getByRole('button')
```

```ts
// Incorrect:
page.locator('[placeholder="Enter some text..."]')
// Correct:
page.getByPlaceholder('Enter some text...')
```

This could also be an extension to `no-raw-locators`, but more like a specific auto-fixer that should be safe to use. For example, we don't use `no-raw-locators` in our codebase because we query plenty of attributes that are fine to use, but a rule like this would be very useful for us.

### Additional contract requirements

- The requested rule is named `prefer-native-locators`.
- In addition to the `aria-label`, `role`, and `placeholder` examples above, convert `alt`, `title`, and test-id attribute selectors to `getByAltText`, `getByTitle`, and `getByTestId`, respectively.
- Convert only a selector that is a single attribute query; leave compound or otherwise more complex selectors unchanged.
