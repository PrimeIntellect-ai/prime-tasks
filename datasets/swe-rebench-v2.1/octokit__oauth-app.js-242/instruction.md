`app.getUserOctokit()` and `octokit.request("GET /user")` does not trigger `"token"` event
**What happened?**

Given I have this code

```js
app.on("token", async () => console.log("token event emitted"))
```

Using `app.getUserOctokit()` and `octokit.request("GET /user")` will not trigger the `"token"` event

```js
const octokit = await app.getUserOctokit({ code });

const { data } = await octokit.request("GET /user");
```

But `app.createToken()` does, as expected.

```js
app.createToken({ code });
```

**What did you expect to happen?**

The first request (`octokit.request("GET /user")`) should have triggered the `"token"` event, as the code exchange happened at this point.

**What the problem might be**

I'm not sure. The first step would be to create a test to replicate the problem
