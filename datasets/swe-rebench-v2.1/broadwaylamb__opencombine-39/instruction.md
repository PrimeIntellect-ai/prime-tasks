CurrentValueSubject is not sending correct value
Hey,

first thanks for this project, I think this can have a huge community impact if we drive it forward and Apple doesn't open-source Combine. I was playing around with it and found a behaviour that I guess is not matching the Apple Combine behaviour.

Take this code:

```swift
let subject = CurrentValueSubject<Int, Never>(0)
subject.send(2)
let c = subject.sink { value in
    print(value)
}
```

Apple's variant is printing `2` but OpenCombine is printing `0`. I tracked down the code and saw that [HIDDEN]. I changed this behaviour but then a lot of tests were failing. Should I open a PR and we can see there, what the correct approach is?

Edit: I opened a PR and every test except 1 is working, which is the synchronisation test. Would be good if you can take a look.

### Additional contract requirements

- After `send(_:)` is called, a subscriber that subscribes afterward must receive the most recently sent input as the subject's current value.
