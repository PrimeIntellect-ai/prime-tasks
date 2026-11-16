Trailing spaces in style attributes break sanitizing
When the value of the style attribute contains trailing spaces the value is omitted entirely due to a parsing issue.

Input:
`<p style="  color:  red  ;  text-align:  center  ;  "></p>`

Expected output:
`<p style="color: red;  text-align: center"></p>`

Actual output:
`<p></p>`
