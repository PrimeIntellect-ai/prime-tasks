Adjustment Factor Bug
If I was matched at decimal odds of 3.2, and the adjustment factor was 75.18, what should the new price be?
From reading this document, I also get 0.79. But how is it possible to get matched at 0.79? 1.01 is the lowest possible odds.
10:01

https://en-betfair.custhelp.com/app/answers/detail/a_id/408/~/exchange%3A-in-a-horse-race%2C-how-will-non-runners-be-treated%3F

The adjustment factor code is here:
https://github.com/liampauling/flumine/blob/4f08f389a3c5c2722b60252055b143cfdfefb0f7/flumine/markets/middleware.py#L104-L107

### Additional contract requirements

- When a runner-removal adjustment affects simulated matched prices, apply the percentage reduction to each matched price and round the result to two decimal places.
- A simulated matched price after a runner-removal adjustment must not be less than 1.01.
