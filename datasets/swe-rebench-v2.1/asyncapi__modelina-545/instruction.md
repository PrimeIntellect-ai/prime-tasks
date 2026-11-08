Wrong property name in JavaCommonPresetOptions
#### Describe the bug
`JavaCommonPresetOptions` interface in `src/generators/java/presets/CommonPreset.ts` defines:
```typescript
export interface JavaCommonPresetOptions {
  equal: boolean;
  hash: boolean;
  classToString: boolean;
}
```
see `hash`

but the actual code expects: `options.hashCode`
```typescript
const shouldContainHashCode = options.hashCode === undefined || options.hashCode === true;
```
https://github.com/asyncapi/modelina/blame/master/src/generators/java/presets/CommonPreset.ts#L7
https://github.com/asyncapi/modelina/blame/master/src/generators/java/presets/CommonPreset.ts#L111

#### How to Reproduce
I found this when trying to generalize creation of JavaGenerator by creating a factory method for it. When I tried to use the example with this interface it obviously failed as (working) example states:
```typescript
    {
      preset: JAVA_COMMON_PRESET,
      options: {
        hashCode: true,
        classToString: true,
      }
    }
```

#### Expected behavior
The options interface should match the actual options of the preset or it shouldn't be exported at all. From simple github search the interface is not used anywhere.

Extra note: maybe it would be nicer to also change `equal` -> `equals` as the generated method is `equals` not `equal` but that would be breaking change.

---

If the fix will be just changing the name of the property I could provide the simple PR.
/my first issue for this project so I didn't start with a PR and from what I see it probably won't be last but im happy to help :)/
