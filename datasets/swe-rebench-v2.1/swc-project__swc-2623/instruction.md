Export assignment retains function types
### Describe the bug

When using the `export =` assignment syntax to mimic `module.exports` behavior as described [here in the handbook](https://www.typescriptlang.org/docs/handbook/modules.html#export--and-import--require), the transpilation leaves the types on a function, which will cause any ECMAScript runtime to crash on loading the code.

### Input code

```typescript
export = function (foo: string, bar: number): boolean {
  return true
}
```


### Config

```json
Default CLI invocation
```


### Playground link

https://swc-play.vercel.app/?version=1.2.106&code=H4sIAAAAAAAAAwXBQQqAMAwEwHtfsUcFX1DwMY2kUtBE1gQE8e%2FO6HM5Ayt62hbDDVN3r7iDw%2FYF0lhheYpyrhD3Q5vhLQA1koZgavl%2BrzUIy0cAAAA%3D&config=H4sIAAAAAAAAA0WNSwrDMAxE76J1ts0id%2BghjKsEF%2F%2FQKBBjfPfawSU7aebpqdIXlrZK2QhYxoQS1Vy0kZbMsOKy0kKKHu3Gg1tfjBysHWG8eudTAs92oeCi28sw2RSyMPBUJh7%2BT7YuCulzjqDez27hSu1xzDuH9wRVTm4%2FOkwQUrUAAAA%3D

### Expected behavior

```javascript
module.exports = function(foo, bar) {
  return true;
};

// Not sure whether this is another bug, but I would expect a single form of exports
export { };
```

### Version

v1.2.94 and above

### Additional context

It used to work up until 1.2.93 and is broken since.

A workaround is to use `export default` and change the usage of the code accordingly, e.g. `require('./module').default`
