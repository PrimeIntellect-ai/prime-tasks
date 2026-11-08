downlevel template literal types
there is missing support for template literal types introduced in [TS 4.1](https://www.typescriptlang.org/docs/handbook/release-notes/typescript-4-1.html#template-literal-types)

### Current Behaviour

```ts
export declare type Greeting = `hello ${World}`
declare type World = 'world'
```

↓↓↓ `downlevel-dts` ↓↓↓

```ts
export declare type Greeting = `hello ${World}`
declare type World = 'world'
```

### Expected Behaviour

```ts
export declare type Greeting = `hello ${World}`
declare type World = 'world'
```

↓↓↓ `downlevel-dts` ↓↓↓

```ts
// Good enough
export declare type Greeting = string
// This would be awesome
export declare type Greeting = `hello world`
declare type World = 'world'
```
