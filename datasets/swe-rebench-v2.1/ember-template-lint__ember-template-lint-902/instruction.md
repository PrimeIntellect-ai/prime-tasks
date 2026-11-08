block-indentation should ignore <pre>
the `block-indentation` rule, in its current state, can be harmful around HTML tags where whitespace is meaningful (i.e., `<pre>`)

To reproduce
```html
      <pre
        class="bg-grey-lighter border border-grey-light text-grey-darkest text-sm font-mono rounded p-3 mt-2 overflow-scroll">.marquee-lightspeed { -webkit-marquee-speed: fast; }
.marquee-lightspeeder { -webkit-marquee-speed: faster; }</pre>
```
I get this linter feedback
```
15:62  error  Incorrect indentation for `pre` beginning at L14:C6.
Expected `</pre>` ending at L15:C62 to be at an indentation of 6 but was found at 56.
block-indentation
```
The whitespace I'd have to add to make the linter happy in this case would result in an undesirable visual change to the rendered HTML (i.e., an extra blank newline at the bottom of each `<pre>`)

### Suggested solution
ignore `<pre>` for this rule

---
##### Versions
ember-cli-template-lint: 1.0.0-beta.3
ember-template-lint: 1.1.0
