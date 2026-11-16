Day 66
Good morning! Here's your coding interview problem for today.

This problem was asked by Square.

Assume you have access to a function toss_biased() which returns 0 or 1 with a probability that's not 50-50 (but also not 0-100 or 100-0). You do not know the bias of the coin.

Write a function to simulate an unbiased coin toss.

### Additional contract requirements

Implement the solution in package `day66`.

Provide a biased coin type `BiasedCoin` with a constructor `NewBiasedCoin(zeroBias int) *BiasedCoin`. `zeroBias` is an integer between 1 and 99 inclusive and gives the percentage probability that a toss returns `0`; the remaining probability returns `1`. The method `(*BiasedCoin).Toss() int` returns `0` or `1` accordingly.

Provide a fair tosser type `FairTosser` with a constructor `NewFairTosser(bc *BiasedCoin) *FairTosser`. The method `(*FairTosser).Toss() int` returns `0` or `1`, each with probability 1/2, regardless of the bias of the supplied coin.
