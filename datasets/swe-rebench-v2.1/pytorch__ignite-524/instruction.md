Average value metric
Discussed on the slack:
> Joost van Amersfoort [7:14 PM]
I have a very simple question, how do I compute an average over a validation set?I have an evaluator engine and I am considering the EpochMetric, and pass `None` as the label and make the compute_fn only average over the first column, or the `RunningAverage` metric with `alpha=1`. However both feel a bit gross for this very simple problem.

> Interesting, looking at the `Loss` source then it indeed seems that it’s very close to what I want and more scalable than EpochMetric. But the problem is that it’s setup for supervised learning and forces len(output) >= 2


Idea is to provide some metric class similar to `Loss` but with no restrictions, just to compute average on provided iteration values.

### Additional contract requirements

Expose the arithmetic-average metric under the public name `Average`. It must accept the iteration value itself, without requiring a prediction/label pair, and be attachable to an evaluator engine to aggregate values from its outputs.
