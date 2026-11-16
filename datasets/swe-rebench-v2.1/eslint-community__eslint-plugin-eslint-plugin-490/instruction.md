Rule: require that properties in a schema include a description
Porting over from https://github.com/typescript-eslint/typescript-eslint/issues/5392: it's theoretically possible for docs generators to use the JSON schema `description` fields on rule options per https://json-schema.org/draft/2020-12/json-schema-core.html#name-schema-vocabularies. That way auto-generated rule docs can automatically be set up with those descriptions.

Is this something you'd be interested in taking in as a core rule here? I'd imagine it wouldn't be something to enable in the _recommended_ config to start given these descriptions aren't used by the default markdown docs generator. But it might be useful long-term as an opt-in option to enforce that the descriptions live in the page somehow?

---

For a concrete example, in typescript-eslint, the `no-explicit-any` rule defines descriptions:

```js
schema: [
  {
    type: 'object',
    additionalProperties: false,
    properties: {
      fixToUnknown: {
        description:
          'Whether to enable auto-fixing in which the `any` type is converted to the `unknown` type.',
        type: 'boolean',
      },
      ignoreRestArgs: {
        description: 'Whether to ignore rest parameter arrays.',
        type: 'boolean',
      },
    },
  },
],
```

...and then https://typescript-eslint.io/rules/no-explicit-any/#options includes them as JSDoc options:

```ts
interface Options {
  /**
   * Whether to enable auto-fixing in which the `any` type is converted to the `unknown` type.
   */
  fixToUnknown?: boolean;
  /**
   * Whether to ignore rest parameter arrays.
   */
  ignoreRestArgs?: boolean;
}

const defaultOptions: Options = [
  { fixToUnknown: false, ignoreRestArgs: false },
];
```

### Additional contract requirements

Expose the rule as `require-meta-schema-description`. Keep it opt-in: it must not be enabled in either the recommended legacy configuration or the recommended flat configuration.
