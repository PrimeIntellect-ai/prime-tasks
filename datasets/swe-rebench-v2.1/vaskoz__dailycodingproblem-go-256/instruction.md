Day 124
Good morning! Here's your coding interview problem for today.

This problem was asked by Microsoft.

You have 100 fair coins and you flip them all at the same time. Any that come up tails you set aside. The ones that come up heads you flip again. How many rounds do you expect to play before only one coin remains?

Write a function that, given n, returns the number of rounds you'd expect to play until one coin remains.

### Additional contract requirements

- Provide a public function `FairCoinFlipDownToOne(coins int) int` in package `day124`.
- For a positive initial coin count, interpret the requested quantity as an integer estimate based on the expected number of coins remaining, not the expected random stopping time. Return the number of rounds until the expected number remaining is no greater than one. Reaching zero coins is terminal too, since at most one coin remains.
