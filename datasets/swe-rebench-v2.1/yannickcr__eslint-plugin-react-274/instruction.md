Rule for `bind` inside JSX
Is that possible to create rule that would throw warning on this code:
```jsx
<a onClick={this.onClick.bind(this, true)}>click me</a>
```
And maybe suggest to do this:
```jsx
<a onClick={() => this.onClick(true)}>click me</a>
```

### Additional contract requirements

- Expose the rule through the plugin’s public rule registry under the name `jsx-no-bind`.
