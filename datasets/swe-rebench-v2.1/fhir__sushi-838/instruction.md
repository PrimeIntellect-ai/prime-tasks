RuleSets not allowing ConceptCaretRules
When attempting to use a ConceptCaretRule in a RuleSet, you receive the following error:
> error Rule of type CodeCaretValueRule cannot be applied to entity of type FshCodeSystem

[HIDDEN]

Example:
```
Alias:   $SCT = http://snomed.info/sct

CodeSystem: SimpleSystem
Title:     "Simple System"
Description: "A simple system"
* insert ConceptWithGermanSynonym(
    #Fish,
    "Fish",
    "It is a fish",
    "Fisch")
* insert ConceptWithGermanSynonym(
    #Seal,
    "Seal",
    "It is a seal",
    "Seehund")

RuleSet: ConceptWithGermanSynonym(code, display, definition, synonym)
* {code} {display} {definition}
* {code} ^designation.language = #de
* {code} ^designation.use = $SCT#900000000000013009 "Synonym"
* {code} ^designation.value = {synonym}
```

https://fshschool.org/FSHOnline/#/share/3zeH3PT

### Additional contract requirements

- A RuleSet must accept `CodeCaretValueRule` rules.
