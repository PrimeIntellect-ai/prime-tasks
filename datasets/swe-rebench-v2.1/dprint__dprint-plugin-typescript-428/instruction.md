conditionalExpression.linePerExpression=false doesn't respect operatorPositon=maintain
**Describe the bug**

dprint-plugin-typescript version: 0.73.1

**Input Code**

```ts
const x = a ? b
    : c ? d
    : e;
```

And config:

```json
{
    "conditionalExpression.linePerExpression": false,
    "operatorPosition": "maintain"
}
```

**Expected Output**

```ts
const x = a ? b
    : c ? d
    : e;
```

**Actual Output**

```ts
const x = a ? b :
    c ? d :
    e;

```

The better answer is probably to pick a style that isn't maintain, and stick with it (but I haven't yet determined the answer for the repo I'm reformatting), but it seems like maintain should continue to maintain things.
