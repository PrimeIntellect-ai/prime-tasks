IMPROVEMENT: Allow Signals to Swap Fragments
Consider the example below:

```tsx
import {Signal} from '@rezact/rezact/signals'

export default function Test() {

  let $elmRef = new Signal(<p>Not Changed</p>);

  const works = () => {
    $elmRef = <span>
      <p>This</p>
      <p>Works</p>
    </span>
  };

  const doesntWork = () => {
    $elmRef = <>
      <p>This</p>
      <p>Doesn't</p>
    </>
  }

  return (
    <>
      {$elmRef}
      <button onClick={works}>Change (works)</button>
      <button onClick={doesntWork}>Change (doesn't)</button>
    </>
  );
}

```

The first button works fine, but clicking the second button stops even the first button from working.  The current code allows swapping HTMLElements, but not Fragments.


https://github.com/Rezact/Rezact/blob/3983220cf8280366599ee67ffc44389adae4b2eb/src/lib/rezact/signals.ts#L135-L143

### Additional contract requirements

- In the JSX Signals example page, provide buttons with accessible names “Change 4”, “Change 5”, and “Change 6”. Their rendered content must toggle, respectively, between “Elm 5” and “Elm 6” together and “Elm 7” and “Elm 8” together; between “Elm 9” and “Elm 10” with “Elm 11” together; and between “Elm 12” and “Elm 13” together and “Elm 14”.
