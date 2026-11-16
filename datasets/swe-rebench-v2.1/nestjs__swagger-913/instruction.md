CLI plugin should support nullable
## I'm submitting a...
<!--
Please search GitHub for a similar issue or PR before submitting.
Check one of the following options with "x" -->
<pre><code>
[ ] Regression <!--(a behavior that used to work and stopped working in a new release)-->
[ ] Bug report
[x] Feature request
[ ] Documentation issue or request
[ ] Support request => Please do not submit support request here, instead post your question on Stack Overflow.
</code></pre>

## Current behavior
```typescript
{
  nullableValOpt?: string | null;
}
```
the type of the field will be `object`:
![image](https://user-images.githubusercontent.com/20422904/90646363-6bed1680-e237-11ea-99aa-87ab44b92801.png)

## Expected behavior
- the type should be `string `
- `nullable `should be `true`
![image](https://user-images.githubusercontent.com/20422904/90646674-c4bcaf00-e237-11ea-934b-98d62f535368.png)


## Environment

Nest version: `@nestjs/swagger": "^4.5.12"`
