Async refinements
Hello,

First of all, thank you very much for your package!

I'm starting using it and I'm running into an issue. I have a piece of code that looks like this:
```ts
input: z.object({
        username: z.string().nonempty().max(100).refine(async username => {
            return await someAsyncFunction(username} == 0
       })
}),
```
I'm doing an async refinement, which should be allowed according to Zod docs. But I am getting this error:
`Async refinement encountered during synchronous parse operation. Use .parseAsync instead.`.

[HIDDEN] Is the fact that we can't use async refinements on purpose?

### Additional contract requirements

- An endpoint input schema containing an asynchronous refinement must be parsed
  successfully, without raising the error
  `Async refinement encountered during synchronous parse operation. Use .parseAsync instead.`.
- When such an asynchronous refinement rejects a value, the endpoint must report a
  normal validation error response (`status: "error"`), and the error message must not
  be the synchronous-parse error
  `Async refinement encountered during synchronous parse operation. Use .parseAsync instead.`.
