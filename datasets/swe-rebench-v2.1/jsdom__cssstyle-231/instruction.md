Fix `background-*` and `background` shorthand
`background` related properties lacks supports for below.

* `background-position` with offset
  * `background-position: left 10px center`
  * `background-position: left center 20px`
  * `background-position: left 10px center 20px`
* `background-repeat` with two values, i.e. shorthand for `background-repeat-x`, `background-repeat-y`
  * `background-repeat: repeat no-repeat`
* `background` shorthand sets / gets longhand values
  * `background: fixed left center repeat url(example.png) green`
* multiple backgrounds
  * `background: fixed left repeat url(example.png), scroll center no-repeat linearGradient(to right, green, blue) green`
