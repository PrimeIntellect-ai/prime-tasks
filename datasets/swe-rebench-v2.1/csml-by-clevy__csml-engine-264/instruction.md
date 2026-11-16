can not use dot notation in variable steps/flows
**Describe the bug**
`goto $something.name` does not work, which is inconvenient in situations like this:

**To Reproduce**
```
start:
  say Question(
    "Where do you want to go next?",
    buttons=[
      Button("A", stepname="stepA") as btnA,
      Button("B", stepname="stepB") as btnB,
    ]
  )
  hold
  do clicked = event.match(btnA, btnB)
  if (clicked) goto $clicked.stepname

  say "Please use one of the buttons!"
  goto start

stepA:
  say "I'm in step A!"
  goto start

stepB:
  say "I'm in step B!"
  goto start
```

### Additional contract requirements

A dotted property on a variable used as a `goto` flow destination must resolve to the flow name, and execution must continue in that flow.
