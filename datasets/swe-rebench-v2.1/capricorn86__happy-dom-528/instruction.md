getByRole cannot query input type=text
Apparently, `happy-dom` thinks textboxes are searchboxes :-)

It was reported over in `dom-testing-library` but they think it's a `happy-dom` bug: https://github.com/testing-library/dom-testing-library/issues/1137

## Environment

```
@testing-library/dom version: 8.11.3
jest: 27.4.7
DOM Environment: happy-dom@3.1.1
```

## Relevant code or config:

```
// UI
      <input
        defaultValue="hello"
        aria-label="name"
        id="name"
        style={{ maxWidth: "280px" }}
        type="text"
      />

// test
  expect(screen.getByRole("textbox", { name: /name/i }));
```

## What you did:

- If you switch to jsdom, it works!
- But with happy-dom, dom-testing-library says that the textbox is a searchbox

## What happened:

```
    TestingLibraryElementError: Unable to find an accessible element with the role "textbox" and name `/name/i`

    Here are the accessible roles:

      searchbox:

      Name "name":
      <input
        aria-label="name"
        defaultvalue="hello"
        id="name"
        style="max-width: 280px;"
        type="text"
      />
```

## Reproduction:
- https://gitlab.com/robotandkid/the-sandbox/-/tree/bug/happy-dom/happy-dom-test
- Run yarn jest

Note that checkboxes have the same problem
