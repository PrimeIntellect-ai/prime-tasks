Day 220
Good morning! Here's your coding interview problem for today.

This problem was asked by Square.

In front of you is a row of N coins, with values `v1, v1, ..., vn`.

You are asked to play the following game. You and an opponent take turns choosing either the first or last coin from the row, removing it from the row, and receiving the value of the coin.

Write a program that returns the maximum amount of money you can win with certainty, if you move first, assuming your opponent plays optimally.

### Additional contract requirements

In package `day220`, provide `AlternatingCoinsFirst(coins []int) int`. It returns the maximum amount the first player can guarantee when both players choose an end coin in turn and the opponent plays optimally.
