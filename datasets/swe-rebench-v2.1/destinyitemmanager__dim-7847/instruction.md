suggester considers incomplete range filters to be complete
once you add the math operator here,
suggester considers the previous filter complete enough that it starts suggesting fresh new filters if you type enough to trigger suggestions
`season:` doesn't trigger this,
`season:<` or `season:=` etc triggers this

![image](https://user-images.githubusercontent.com/68782081/107032129-29c57c00-6768-11eb-852a-1f3a268b1bd9.png)

### Additional contract requirements

When the user is still typing the value of a range filter after a comparison operator, autocomplete must not suggest additional filter terms as though the range expression were complete. It may still suggest completions for the active range value.
