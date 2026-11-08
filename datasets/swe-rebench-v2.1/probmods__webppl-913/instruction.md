HMC samples out of support
This may be a case of #343? Here's a simple program that (often but not always) errors with `Parameter "p" should be of type "real [0, 1]"` and if you print out the offending variable, it's often slipping above 1.

```
var inferOpts = {method: 'MCMC', kernel: {HMC: {steps: 50, stepSize: .01}},
                 samples: 5000}
var results = Infer(inferOpts, function() {
  var p1 = uniform(0.5, 1)
  var p2 = uniform(0, p1)
  if(p2 > 1) {
    print(p1)
    print(p2)
  }
  observe(Bernoulli({p: p2}), false)
  return p1
})
```
This runs ok with the MH kernel.
