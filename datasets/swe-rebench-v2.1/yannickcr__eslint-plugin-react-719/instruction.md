Rule proposal: prevent both children and dangerouslySetInnerHTML at the same time
React will issue a warning if you try to use dangerouslySetInnerHTML and children at the same time.

https://github.com/facebook/react/blob/85dcbf83/src/renderers/dom/shared/ReactDOMComponent.js#L170

This should be easy enough to enforce for most cases with a linter rule.

Bad:

```jsx
<div dangerouslySetInnerHTML={{ __html: 'HTML' }}>
  Children
</div>
```

Good:

```jsx
<div dangerouslySetInnerHTML={{ __html: 'HTML' }} />
```

```jsx
<div>
  Children
</div>
```

### Additional contract requirements

- The rule must be available from the plugin under the name `no-danger-with-children`.
- When reporting this conflict, use the message ``Only set one of `children` or `props.dangerouslySetInnerHTML` ``.
- Do not report when a React element provides only children or only `dangerouslySetInnerHTML`, including elements created with JSX or `React.createElement`.
