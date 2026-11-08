"Generate function" code action doesn't take labels into account
At the moment if I have a function that doesn't exist and is also using labels like this: `wibble(wobble: 1)`, the "Generate function" code action will generate a function that has no labels and so will be invalid. It would be nice if it took labels into account as well. One think I'm not sure how to deal with is what to do when the labels are not right:
- If there's duplicate labels should we generate an invalid function with duplicate labels? Or should the LS not prompt any action at all?
- If there's an unlabelled argument after labelled ones should the language server generate an invalid function with labelled arguments in the wrong place, a valid function but without the wrong-positioned labels, or should it refuse to generate anything at all?

### Additional contract requirements

- Do not offer the code action when an unlabelled argument follows a labelled argument, or when argument labels are repeated.
