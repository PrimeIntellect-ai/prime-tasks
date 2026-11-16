Comments are removed from inline event listeners
For instance
```jsx
<svelte:body on:keydown={(e) => {
	// hello world
}} />
// -- PRETTIER ->
<svelte:body on:keydown={(e) => {}} />
```
