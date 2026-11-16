<Repeat/> does not update when its times.prop changes
### Describe the bug

```tsx
function Counter() {
  const [count, setCount] = createSignal(2);
  const increment = () => setCount((count) => count + 1);
  const decrement = () => setCount((count) => count - 1);

  return (
    <>
      <button onClick={increment}>increment</button>
      <button onClick={decrement}>decrement</button>
      <Repeat times={count()}>{() => "hallo"}</Repeat>
    </>
  );
}
```

steps to reproduce bug:
- initial render: `hallohallo`
- press decrement: stays `hallohallo`
- press increment: stays `hallohallo`
- only when times becomes 0 it will render empty

[I was able to narrow the bug to the usage of `createMemo` in `<Repeat/>`](https://playground.solidjs.com/anonymous/cfa666cf-17cc-4aca-a091-a19f949bd2a5)

### Minimal Reproduction Link

https://playground.solidjs.com/anonymous/6c6feac1-bd0d-41f1-b6ec-61bca51182e3
