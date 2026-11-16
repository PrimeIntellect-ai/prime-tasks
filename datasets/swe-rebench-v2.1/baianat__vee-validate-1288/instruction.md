reset counter of vv-id for consecutive snapshot tests
#### Versions:
- VueJs: #.#.#
- Vee-Validate: 2.0.6

### Description:
vee-validate generates a ID for each field that it's applied to when they're rendered. This means that if you're using Jest snapshots, or any other test framework that supports snapshots, they will include this id. When you run 2 consecutive tests on a component that has a input field the first snapshot test will save data-vv-id=1 and the second test will save data-vv-id=2.
If we want to run the **second** test individual the snapshot will contain vv-id=1.

I found an old related issue https://github.com/baianat/vee-validate/issues/1000
But at the moment vee-validate doesn't use Math.random anymore so i can't overrule the generation of a unique id.

Is there a way i can reset the vv-id count
[HIDDEN]

### Steps To Reproduce:
- store 2 snapshots with 2 consecutive tests
- run the second test individually

### Additional contract requirements

- Generated snapshot markup for equivalent field renders must remain identical across consecutive renders and when either render is produced independently; it must not depend solely on an accumulated vv-id count.
