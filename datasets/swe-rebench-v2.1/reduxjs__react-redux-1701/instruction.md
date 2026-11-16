selector in useSelector called one more time after forceUpdate inside hook
**What is the current behavior?**

When state changed, selector recomputes, and value sets into latestSelectedState. Component will re-render, and selector recomputes again, but its value already in latestSelectedState.current

(selector is arrow function - `const data = useSelector((state) => state.data);`)

**What is the expected behavior?**

Selector recomputes once

I can open PR to fix this, but I don't know, may be selector specially calls twice for some reasons
