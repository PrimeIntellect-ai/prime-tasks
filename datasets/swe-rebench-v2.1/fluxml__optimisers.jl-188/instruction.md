Implementation of `AdamW` differs from PyTorch
Hi, thank you for developing and maintaining this awesome library and ecosystem!

I'm not entirely sure but could it be that the documentation for the `AdamW` optimizer is a bit misleading? If I understand correctly, then [its definition](https://github.com/FluxML/Flux.jl/blob/master/src/optimise/optimisers.jl#L502) of

```
AdamW(η = 0.001, β = (0.9, 0.999), decay = 0) = Optimiser(Adam(η, β), WeightDecay(decay))
```

means that it performs this update (where $-\eta A$ is Adam's update):

$$
\begin{align*}
\theta_t \leftarrow \theta_{t-1} - \eta A + \texttt{decay} \  \theta_{t-1}
\end{align*}
$$

However, the paper on AdamW (which is linked to by the docs) parametrizes this differently as:

$$
\begin{align*}
\theta_t \leftarrow \theta_{t-1} - \eta (\alpha A + \lambda \theta_{t-1})
\end{align*}
$$

I.e. Flux's `eta` corresponds to the paper's $\eta\alpha$ and Flux's `decay` corresponds to the paper's $\eta \lambda$.

This is probably super unimportant (in that case, sorry for the noise) but since I just noticed this during bug hunting in an implementation of mine (which uses AdamW), I thought I'd report it.

### Additional contract requirements

By default, AdamW scales the weight-decay contribution by the learning rate. Its parameter update is `x_new = x_old - eta * (d_adam + lambda * x_old)`, where `d_adam` is Adam's update with learning rate one.
