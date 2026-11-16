auto-generated message ID override id in V3
**Describe the bug**
Auto-generated message ID overrides `id` property in the `Trans` component.  This component
` <Trans id="msg.hello">Hello World</Trans>` will transfformed to ` <Trans id="Hello World"></Trans>`.

**To Reproduce**

```
import { Trans } from "@lingui/react"

export default function App() {
   return <Trans id={"msg.hello"}>Hello World</Trans>
}
```

**Expected behavior**
The `id` should override the auto-generated message ID.

**Additional context**


- jsLingui version ``3.0.0-7``

.linguirc
```
{
  "catalogs": [
    {
      "path": "<rootDir>/translations/{locale}/messages",
      "include": [
        "<rootDir>"
      ],
      "exclude": [
        "*/node_modules/*"
      ]
    }
  ],
  "locales": [
    "de",
    "es"
  ],
  "format": "po"
}
```

### Additional contract requirements

- The macro transformer emits the resolved message ID as a quoted JSX string attribute, i.e. `id="msg.hello"`, regardless of whether the source supplied the `id` as a string literal (`id="msg.hello"`), an expression container holding a string literal (`id={"msg.hello"}`), or a static template literal (`` id={`msg.hello`} ``). The original expression syntax is not preserved in the transformed output.
- When the supplied `id` differs from the auto-generated message (the children text), the children text is emitted as a `message` attribute in non-production builds, e.g. `<Trans id="msg.hello" message="Hello World" />`.
