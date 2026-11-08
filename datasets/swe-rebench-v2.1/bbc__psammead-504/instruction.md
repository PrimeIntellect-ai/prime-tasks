Remove text attribute of SubHeading
**Is your feature request related to a problem? Please describe.**
The current [SubHeading implementation requires a `text` attribute](https://github.com/BBC-News/psammead/pull/79/files#diff-fc2971529aafcd7309bd4480db209567R10) which duplicates the children. Example:

```jsx
<SubHeading text="This is a SubHeading">This is a SubHeading</SubHeading>
```

**Describe the solution you'd like**
This should not be necessary. A SubHeading should be rendered via:

```jsx
<SubHeading>This is a SubHeading</SubHeading>
```

The `text` attribute currently is used in ID generation so that headings can be used to anchor content. We are not sure where this requirement came from, but believe it should be handled at the container level rather than the presentational component level, and that the `id` prop should be optional.

```jsx
<SubHeading id="optional-id (to be passed at container level)">This is a SubHeading</SubHeading>
```

**Testing notes**
Regression testing across devices & desktop, including accessibility checks to make sure the text still reads as it currently does on Live.

Dev insight: snapshot tests covering when you do and don't pass the ID.

- [x] Initially labelled with ["Refinement needed"](https://github.com/BBC-News/psammead/labels/Refinement%20Needed)
