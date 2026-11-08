Prop isArray is incorrectly added when using @ApiQuery decorator with enum values
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
Applying an `APIQuery` decorator to a controller method which uses an enum:

<pre><code>@ApiQuery({
    name: 'pagingStrategy',
    type: 'enum',
    required: false,
    enum: ['withCount', 'noCount'],
  })</code></pre>

produces json:

<pre><code>{
    "name": "pagingStrategy",
    "required": false,
    "in": "query",
    "isArray": false,
    "schema": {
        "enum": [
            "withCount",
           "noCount"
        ],
        "type": "string"
    }
}</code></pre>

When converted to yaml and pasted into the Swagger Editor produces validation errors as the `isArray` property should not exist.

Manually removing the isArray property in the [Swagger Editor ](https://editor.swagger.io/) solves the issue.

## Expected behavior

The `isArray` property should not be present when a query parameter is an enum value.

## Minimal reproduction of the problem with instructions

[Minimal Reproduction Repo](https://github.com/tourlbr/nesting)

**Instructions**

1. Using the default nest setup add an ApiQuery decorator to the endpoint method and retrieve the json version of the OpenApi spec (-json in URL).
2. Paste into the [Swagger Editor](https://editor.swagger.io/)

## What is the motivation / use case for changing the behavior?

To create valid OpenAPI documents.

## Environment

<pre><code>
Nest version: 7.5.1

For Tooling issues:
- Node version: v14.12.0
- Platform:  Mac

</code></pre>
