apply_gradients AttributeError: 'ResourceVariable' object has no attribute 'overwrite_with_gradient'
When I have a mix of tf.Variable and KerasVariables I get the following error:
```
--> 632     if v.overwrite_with_gradient:
    633         if self.gradient_accumulation_steps:
    634             # Utilize a stateless manner for JAX compatibility
    635             steps = self.gradient_accumulation_steps

AttributeError: 'ResourceVariable' object has no attribute 'overwrite_with_gradient'
```

I suspect this is because my list of variables is [KerasVariables] + [tf.Variables]
and [HIDDEN]
https://github.com/keras-team/keras/blob/660da946d33ccbb53575f15a17abdfd725cd2086/keras/src/optimizers/base_optimizer.py#L675

### Additional contract requirements

Applying gradients to a mixture of Keras variables and TensorFlow variables must process the supplied variables without failing solely because of their variable type. When some gradients are missing, the optimizer must warn about the missing gradients and still apply the available gradients.
