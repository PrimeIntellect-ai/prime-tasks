Type of prop with a default value is incorrect
When upgrading to v1.0.0-rc.4, I'm getting a lot of type errors on components using props with a default value.
It looks like #655 introduced this regression.

Using the following component, the `props` argument of `setup()` is typed differently between rc.3 and rc.4:

```ts
export default defineComponent({
  props: {
    id: { type: String, default: 'def' },
    count: { type: Number, required: true },
  },
  setup(props) {},
});
```

rc.3:
```ts
props: {
    id: string;
    count: number;
} & {}
```

rc.4:
```ts
props: {
    count: number;
} & {
    id?: string | undefined;
}
```

rc.4 is incorrect here as the `id` prop will never be `undefined` at runtime, as it receives the default value if one wasn't provided.
