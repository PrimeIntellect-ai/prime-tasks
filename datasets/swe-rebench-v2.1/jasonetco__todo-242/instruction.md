[BUG] NEED boundary check of TODO
**Describe the bug**

It creates an issue unexpectedly.

**To Reproduce**

When I write a comment in javascript code.
```js
/*
 * OTODOKE_HOPE_TIME
 */
```

**Expected behavior**
It creates an issue because O`TODO`KE has `TODO`. but, I want to do nothing.

**Screenshots**
<img width="550" alt="Screen Shot 2020-01-09 at 14 53 52" src="https://user-images.githubusercontent.com/128431/72041822-e7750580-32ef-11ea-8b2a-5648694856e1.png">

**Additional context**

maybe need some boundary checks when we detecting TODO.
