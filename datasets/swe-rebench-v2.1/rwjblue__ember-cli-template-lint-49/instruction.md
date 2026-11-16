Incorrect expectation of </input>
Hey, maybe my indentation is weird here but I think no error should show up for this:
```handlebars
<input
  type="text"
  value={{if extra.labelPath (get selected extra.labelPath) selected}}
  class="ember-power-select-typeahead-input"
  oninput={{action "search" value="target.value"}}
  onkeydown={{action "onkeydown"}}
  onmousedown={{action "onmousedown"}}>
```
But I'm getting the following error:
```
Incorrect indentation for `input` beginning at ('code/templates/components/input-trigger.hbs'@ L1:C0). Expected `</input>` ending at ('code/templates/components/input-trigger.hbs'@ L7:C44)to be at an indentation of 0 but was found at 36.
```
If i put the input closing `>`char on the next line at position 0 I get ``indentation of 0 but was found at -7.`` which is weird, no?

No error is thrown if I put the whole input in a single line. Or like this:
```handlebars
<input
  type="text"
  value={{if extra.labelPath (get selected extra.labelPath) selected}}
  class="ember-power-select-typeahead-input"
  oninput={{action "search" value="target.value"}}
  onkeydown={{action "handleKeydown"}}
  onmousedown={{action "captureMouseDown"}}
       >
```
I understand why this is happening, but should an error be thrown here? If yes, maybe the expectation of the closing ">" char position should be different.

Thanks a lot in advance!
