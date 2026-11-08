`_check_discrete_dependance` can become very slow for models with many discrete variable
### Description

My team has recently move up to openmdao 3.33.0 (our project was previously pinned at 3.17.0, which was getting a little dated). Upon upgrading, it seems that many of the optimizations that used to sit in the 30 seconds to 2 minute runtime zone saw a notable increase in run time. After some debugging, it seems like a large source of the runtime difference is `_TotalJacInfo._check_discrete_dependence()`.

The models we use tend to be quite discrete variable heavy. In version 3.17.0 the first call to `compute_totals` is usually 0.5-2 seconds, whereas in 3.33.0 this has jumped to 15-30 seconds for the first call.

We're going to look at swapping a good portion of these discrete outputs to become options to get things back up to the speeds they were at before, but I figured I'd make an issue just to make a note that this can be an area where performance is affected for discrete variable heavy models.

In the meantime though, is there any way to make openmdao skip this check?

Thanks

### Example

Unfortunately I can't provide a copy of the models

### OpenMDAO Version

3.33.0

### Relevant environment information

_No response_

### Additional contract requirements

- When `compute_totals()` raises an error because a total derivative depends upon a discrete output variable, the message must be exactly `Total derivative of 'C3.y' with respect to 'x' depends upon discrete output variables ['G.G1.C1.y'].`
- Ordinary `compute_totals()` calls, with no extra arguments, must not become dramatically slower when the model contains many discrete outputs that no total derivative depends upon. Such a model must take no more than a small constant factor longer than the same model without those discrete outputs, plus a small fixed allowance for timing noise.
