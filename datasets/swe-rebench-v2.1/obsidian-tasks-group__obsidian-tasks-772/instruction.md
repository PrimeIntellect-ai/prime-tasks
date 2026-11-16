Allow capital letters in abbreviations for dates in Create/Edit Modal
## Expected Behavior

That abbreviations in dates should be recognised even if the device insists on capitalising the first letter I type

## Current Behavior

My iPad keyboard always capitalises the first letter I type, meaning I get 'invalid due date' when I try and use the new abbreviations.

<img width="250" alt="Invalid due date with capital letter" src="https://user-images.githubusercontent.com/4840096/173228863-8fa4813d-534a-4fac-8b83-c7072b751667.png">

## Steps to Reproduce

- Install the distribution in https://github.com/obsidian-tasks-group/obsidian-tasks/actions/runs/2479616619 And restart.
- Open the Create/edit Task modal
- Type in `Td` and a space in Due field
- expected: it expands to `todays
- actual: it says `invalid due date`


## Context (Environment)
* Obsidian version: 1.2.2 (56) on iPad
* Tasks version: development version 9092620cad90f0b77a1f23964b6afe6c5ff0ea5c
* [ ] I have tried it with all other plugins disabled and the error still occurs

## Possible Solution
<!--- Not obligatory, but suggest a fix/reason for the bug, if you have an idea -->

- Make the abbreviation code ignore case
