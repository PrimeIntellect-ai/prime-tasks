SVG void elements don't have a slash
Temple is amazing so far. Thanks for this library.

**Describe the bug**
SVG void elements nest siblings without a self-closing slash

**To Reproduce**
Steps to reproduce the behavior:
```elixir
def test do
  temple do
    rect width: "256"
    circle cx: "128"
  end
end
# "<rect width=\"256\">\n<circle cx=\"128\">\n"
```

In browser, unintended closing tag is added

```html
<!-- -->
<rect width="256">
  <circle cx="128">
</rect>
```

**Expected behavior**
A clear and concise description of what you expected to happen.

```elixir
rect width: "256"
circle cx: "128"
```

Should result in

```html
<!-- In browser, unintended closing tag is added -->
<rect width="256" />
<circle cx="128" />
```

Should equal

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Desktop (please complete the following information):**
 - OS: macOS Monterey 12.7.6
 - Temple Version: 13
 - Elixir Version: 1.17
 - Erlang Version: 27

**Additional context**
Add any other context about the problem here.

Current workaround is `/: true` attribute.

I think Temple could add a slash to all self-closing tags because HTML has no problem with them.
