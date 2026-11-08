Allow users to modify RStudio Connect index.html file
We're releasing some wrappers around pins for internal use, and we wanted to change the material which is printed in the Rstudio Connect gui, so that it would recommend our wrappers rather than `pin_get`.

I did this in a fairly simple way by allowing the user to point to a different index.html file  which I'm happy to submit in a pull request if it's helpful: https://github.com/GShotwell/pins/blob/master/R/board_rsconnect_bundle.R#L4-L9

Another option for solving this problem might include some kind of pins/Rmarkdown hybrid (pindown) whereby the Rmarkdown was rendered as the front matter for the pin. This is probably more use friendly, but also a bit more complicated.

### Additional contract requirements

Users can provide the path to their alternate page through the `RSCONNECT_HTML_PATH` R option. When a pin is created for RStudio Connect, the supplied HTML must replace the default `index.html` page bundled for that pin.
