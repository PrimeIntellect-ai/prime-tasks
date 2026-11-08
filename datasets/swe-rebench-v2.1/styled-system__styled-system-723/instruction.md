Using other props in a system() definition
Is there a way to use other component props in a `system()` definition?

I currently have:
```javascript
const sidebarSystemSpacing = system({
  spacing: {
    property: 'margin',
    scale: 'sidebar.spacing',
    transform: (value, scale) => `calc(${scale[value]}px / 2)`,
  },
})
```

If I wanted another prop to influence this calculation (for example, `minSpacing`), how would I achieve that? Is it possible? Here's ultimately what I want to achieve:
```javascript
const sidebarSystemSpacing = system({
  spacing: {
    property: 'margin',
    scale: 'sidebar.spacing',
    transform: (value, scale) => `calc(${props.contentMin} - ${scale[value]}px / 2)`,
  },
})
```

Thanks!

### Additional contract requirements

- A `transform` callback configured with `system()` must receive the raw prop value, the resolved scale, and the full props object passed to the returned parser, in that order.
