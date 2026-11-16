Array of enums not working as expected
<!--
PLEASE HELP US PROCESS GITHUB ISSUES FASTER BY PROVIDING THE FOLLOWING INFORMATION.

ISSUES MISSING IMPORTANT INFORMATION MAY BE CLOSED WITHOUT INVESTIGATION.
-->

## I'm submitting a...
<!--
Please search GitHub for a similar issue or PR before submitting.
Check one of the following options with "x" -->
<pre><code>
[ ] Regression <!--(a behavior that used to work and stopped working in a new release)-->
[x] Bug report
[ ] Feature request
[ ] Documentation issue or request
[ ] Support request => Please do not submit support request here, instead post your question on Stack Overflow.
</code></pre>

## Current behavior
Adding an array of enums with the ApiProperty does not seem to work correctly.  For example, given the following enum:
```
enum MyEnum {
  One = "one",
  Two = "two"
}
```
I want to use this with a model property as follows:
`@ApiProperty({ enum: MyEnum, enumName: 'MyEnum',  isArray: true })`

This does not render correctly in the UI, and shows a type of `{}`

I've also tried both of these:
`@ApiProperty({ enum: MyEnum, enumName: 'MyEnum',  type: 'array' })`
and
`@ApiProperty({ type: "array", enum: MyEnum, enumName: 'MyEnum', items: { $ref: getSchemaPath('MyEnum')} })`

## Expected behavior
I'd expect the property to show up as an array with a reference to MyEnum.

I'd expect the result of `@ApiProperty({ enum: MyEnum, enumName: 'MyEnum',  isArray: true })` to add `"type": "array"`.


## Minimal reproduction of the problem with instructions
Let me know if this is needed, I'd be happy to provide.

## What is the motivation / use case for changing the behavior?
N/A

## Environment

<pre><code>
Nest version: 7.1.3
Nest Swagger 4.5.10
<!-- Check whether this is still an issue in the most recent Nest version -->

For Tooling issues:
- Node version: 12.18
- Platform:  Mac
- NestJS: 4.5.10

Others:
N/A
