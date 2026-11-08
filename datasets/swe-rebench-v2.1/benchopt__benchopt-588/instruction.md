API rename stopping_strategy to sampling_strategy
It would make the way benchopt samples convergence curves easier to understand, whereas now there can be a confusion between stopping_strategy (how is the curved sampled) and stopping_criterion (where does the curve stop)
