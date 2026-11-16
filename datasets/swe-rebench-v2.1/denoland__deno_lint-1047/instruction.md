Problem in `finally` block
Not a big issue but I don't think `deno lint` should throw a `no-unreachable` problem here. I could prevent the problem by moving the `return` statement outside the block.

### Lint Name
`no-unreachable`

### Code Snippet

```ts
private async handleContext(ctx: Context<S>): Promise<Response> {
    try {
      ctx = await this.invokeHandlers(ctx, this.routes);
    } catch (error) {
      ctx.error = error;
      ctx = await this.invokeHandlers(ctx, this.catchRoutes);
    } finally {
      ctx = await this.invokeHandlers(ctx, this.finallyRoutes);
      return ctx.response;
    }
  }
```

### Expected Result

Nothing being thrown

### Version

deno 1.20.1 (release, x86_64-unknown-linux-gnu)
v8 10.0.139.6
typescript 4.6.2
