const module imports not substituted in exported functions
### Describe the bug

When importing a value from a const module, references to it within an exported function aren't substituted

### Input code

```typescript
import foo from 'some-const-module';
console.log(foo);
export function _() {
  console.log(foo);
}
```


### Config

```json
{ jsc: { constModules: { globals: {
  'some-const-module': { default: '...' }
} } } }
```


### Playground link

_No response_

### Expected behavior

```javascript
console.log('...');
export function _() {
  console.log('...');
}
```

### Actual behavior

```javascript
console.log('...');
export function _() {
  console.log(foo);
}
```

### Version

1.3.71

### Additional context

_No response_
