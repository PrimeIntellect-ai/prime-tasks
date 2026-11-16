Bug: comma separated arrays not parsed correctly from encoded url
Test case:

```ts
it('should parse arrays correctly', () => {
    const search =
      '?testA%5B%5D=1&testB%5B%5D=a%2Cb%2Cc%2Cd%2Ce%2Cf&testC=true';

    const result = queryString.parse(search, {
      parseBooleans: true,
      parseNumbers: true,
      arrayFormat: 'bracket-separator',
    });

    expect(result).toEqual({
      testA: [1],
      testB: ['a', 'b', 'c', 'd', 'e', 'f'],
      testC: true,
    });
  });
```

results in:

![image](https://github.com/user-attachments/assets/8c40a304-30ee-4ab5-bb50-88a2a3d187a6)

when it's unencoded it works fine:

```ts
it('should parse arrays correctly', () => {
    const search =
      '?testA%5B%5D=1&testB%5B%5D=a,b,c,d,e,f&testC=true';

    const result = queryString.parse(search, {
      parseBooleans: true,
      parseNumbers: true,
      arrayFormat: 'bracket-separator',
    });

    expect(result).toEqual({
      testA: [1],
      testB: ['a', 'b', 'c', 'd', 'e', 'f'],
      testC: true,
    });
  });
```

Library version: 9.1.0
