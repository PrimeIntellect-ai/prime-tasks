Bug when formatting multiple assigns
This seems like a super wierd but severe bug. It seems like when having more than nine assigns in a string interpolation, all following string interpolations will be malformatted!

## Steps to reproduce

Format the following `.heex` code:

```heex
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />

<div text={"bar: #{@bar}"} />
<div text={"bar: #{@bar}"} />
<div text={"bar: #{@bar}"} />
```

The expected outcome is that the code should be the same.

## Outcome

```heex
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />
<div text={"foo: #{@foo}"} />

<div text={"bar: #{@foo}0"} />
<div text={"bar: #{@foo}0"} />
<div text={"bar: #{@foo}0"} />
```

## Configuration

Using `tailwind_formatter 0.3.2`, `.formatter.exs`:
```elixir
[
  plugins: [TailwindFormatter],
  inputs: ["*.{ex,exs}", "priv/*/seeds.exs", "{config,lib,test}/**/*.{ex,exs,heex}"],
  subdirectories: ["priv/*/migrations"]
]
