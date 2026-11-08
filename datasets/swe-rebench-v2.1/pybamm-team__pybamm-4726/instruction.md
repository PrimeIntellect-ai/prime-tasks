[Bug]: Multi-particle model does not work with stoichiometry-dependent solid diffusivity
### PyBaMM Version

23.9

### Python Version

3.10

### Describe the bug

I am getting an error when running a multi-particle DFN with a stoichiometry-dependent solid particle diffusivity:
`UnboundLocalError: local variable 'matrix' referenced before assignment`

It seems that the `integration_dimension` is set to tertiary when there is stoichiometry-dependent solid particle diffusivity, but tertiary integration_dimension is [not yet implemented here](https://github.com/pybamm-team/PyBaMM/blob/6851496ff1a9cc3ec1573033cec28a2353857fbf/pybamm/spatial_methods/finite_volume.py#L216).

### Steps to Reproduce

Create a MP-DFN model

```
options = {
        "particle size": "distribution"
}

model = pybamm.lithium_ion.DFN(options = options)

where the solid diffusivity functional form is sto dependent
for example:
def particle_diffusivity(sto, T):

    D_ref = 1 * 10 ** (-13)
    E_D_s = 18550
    arrhenius = np.exp(E_D_s / pybamm.constants.R * (1 / 298.15 - 1 / T))

    return D_ref * arrhenius * (sto + 0.2) * 10

params = pybamm.ParameterValues("Marquis2019")
params = pybamm.get_size_distribution_parameters(params)
params.update({
        "Positive electrode diffusivity [m2.s-1]": particle_diffusivity
})

```

### Relevant log output

```shell
`2023-11-21 11:58:27.134 - [INFO] discretisation.remove_independent_variables_from_rhs(1134): removing variable Discharge capacity [A.h] from rhs
2023-11-21 11:58:27.137 - [INFO] discretisation.remove_independent_variables_from_rhs(1134): removing variable Throughput capacity [A.h] from rhs
---------------------------------------------------------------------------
KeyError                                  Traceback (most recent call last)
File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/discretisations/discretisation.py:728, in Discretisation.process_symbol(self, symbol)
    727 try:
--> 728     return self._discretised_symbols[symbol]
    729 except KeyError:

KeyError: Addition(-0x20be135ef0fe3268, +, children=['2.0000000000000003e-13', 'x-average(1e-12 * (maximum(minimum(1.9524414269595433e-05 * Positive particle concentration distribution [mol.m-3], 0.9999999999), 1e-10)))'], domains={'primary': ['positive particle'], 'secondary': ['positive particle size'], 'tertiary': ['current collector']})

During handling of the above exception, another exception occurred:

KeyError                                  Traceback (most recent call last)
File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/discretisations/discretisation.py:728, in Discretisation.process_symbol(self, symbol)
    727 try:
--> 728     return self._discretised_symbols[symbol]
    729 except KeyError:

KeyError: XAverage(-0x67124ee27e56970a, x-average, children=['1e-12 * (maximum(minimum(1.9524414269595433e-05 * Positive particle concentration distribution [mol.m-3], 0.9999999999), 1e-10))'], domains={'primary': ['positive particle'], 'secondary': ['positive particle size'], 'tertiary': ['current collector']})

During handling of the above exception, another exception occurred:

KeyError                                  Traceback (most recent call last)
File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/discretisations/discretisation.py:728, in Discretisation.process_symbol(self, symbol)
    727 try:
--> 728     return self._discretised_symbols[symbol]
    729 except KeyError:

KeyError: Multiplication(-0x97cfd4073097872, *, children=["1.0 / integral dx_p ['positive particle'](broadcast(1.0))", "integral dx_p ['positive particle'](1e-12 * (maximum(minimum(1.9524414269595433e-05 * Positive particle concentration distribution [mol.m-3], 0.9999999999), 1e-10)))"], domains={'primary': ['positive particle'], 'secondary': ['positive particle size'], 'tertiary': ['current collector']})

During handling of the above exception, another exception occurred:

KeyError                                  Traceback (most recent call last)
File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/discretisations/discretisation.py:728, in Discretisation.process_symbol(self, symbol)
    727 try:
--> 728     return self._discretised_symbols[symbol]
    729 except KeyError:

KeyError: Division(-0x3f2cb559d729ce0e, /, children=['1.0', "integral dx_p ['positive particle'](broadcast(1.0))"], domains={'primary': ['positive particle'], 'secondary': ['positive particle size'], 'tertiary': ['current collector']})

During handling of the above exception, another exception occurred:

KeyError                                  Traceback (most recent call last)
File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/discretisations/discretisation.py:728, in Discretisation.process_symbol(self, symbol)
    727 try:
--> 728     return self._discretised_symbols[symbol]
    729 except KeyError:

KeyError: Integral(-0x3d067ca2936c7ceb, integral dx_p ['positive particle'], children=['broadcast(1.0)'], domains={'primary': ['positive particle'], 'secondary': ['positive particle size'], 'tertiary': ['current collector']})

During handling of the above exception, another exception occurred:

UnboundLocalError                         Traceback (most recent call last)
Cell In[86], line 20
     14 for model in models:
     15     sim = pybamm.Simulation(model,
     16                             parameter_values=params,
     17 #                             experiment=experiment,
     18                            )
---> 20     sol = sim.solve(
     21         [0, 10],
     22 #         initial_soc="4 V"
     23     )
     24     sims.append(sol)
     25 sol.plot()

File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/simulation.py:546, in Simulation.solve(self, t_eval, solver, check_model, save_at_cycles, calc_esoh, starting_solution, initial_soc, callbacks, showprogress, **kwargs)
    544 if self.operating_mode in ["without experiment", "drive cycle"]:
    545     print(build_inputs)
--> 546     self.build(check_model=check_model, initial_soc=initial_soc, inputs=build_inputs)
    547     if save_at_cycles is not None:
    548         raise ValueError(
    549             "'save_at_cycles' option can only be used if simulating an "
    550             "Experiment "
    551         )

File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/simulation.py:427, in Simulation.build(self, check_model, initial_soc, inputs)
    425 self._mesh = pybamm.Mesh(self._geometry, self._submesh_types, self._var_pts)
    426 self._disc = pybamm.Discretisation(self._mesh, self._spatial_methods)
--> 427 self._built_model = self._disc.process_model(
    428     self._model_with_set_params, inplace=False, check_model=check_model
    429 )
    430 # rebuilt model so clear solver setup
    431 self._solver._model_set_up = {}

File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/discretisations/discretisation.py:214, in Discretisation.process_model(self, model, inplace, check_model, remove_independent_variables_from_rhs)
    210 # Discretise variables (applying boundary conditions)
    211 # Note that we **do not** discretise the keys of model.rhs,
    212 # model.initial_conditions and model.boundary_conditions
    213 pybamm.logger.verbose("Discretise variables for {}".format(model.name))
--> 214 model_disc.variables = self.process_dict(model.variables)
    216 # Process parabolic and elliptic equations
    217 pybamm.logger.verbose("Discretise model equations for {}".format(model.name))

File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/discretisations/discretisation.py:698, in Discretisation.process_dict(self, var_eqn_dict, ics)
    695         eqn = pybamm.FullBroadcast(eqn, broadcast_domains=eqn_key.domains)
    697 pybamm.logger.debug("Discretise {!r}".format(eqn_key))
--> 698 processed_eqn = self.process_symbol(eqn)
    699 # Calculate scale if the key has a scale
    700 scale = getattr(eqn_key, "scale", 1)

File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/discretisations/discretisation.py:730, in Discretisation.process_symbol(self, symbol)
    728     return self._discretised_symbols[symbol]
    729 except KeyError:
--> 730     discretised_symbol = self._process_symbol(symbol)
    731     self._discretised_symbols[symbol] = discretised_symbol
    732     discretised_symbol.test_shape()

File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/discretisations/discretisation.py:766, in Discretisation._process_symbol(self, symbol)
    764 left, right = symbol.children
    765 disc_left = self.process_symbol(left)
--> 766 disc_right = self.process_symbol(right)
    767 if symbol.domain == []:
    768     return pybamm.simplify_if_constant(
    769         symbol._binary_new_copy(disc_left, disc_right)
    770     )

File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/discretisations/discretisation.py:730, in Discretisation.process_symbol(self, symbol)
    728     return self._discretised_symbols[symbol]
    729 except KeyError:
--> 730     discretised_symbol = self._process_symbol(symbol)
    731     self._discretised_symbols[symbol] = discretised_symbol
    732     discretised_symbol.test_shape()

File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/discretisations/discretisation.py:789, in Discretisation._process_symbol(self, symbol)
    787         v = pybamm.ones_like(child)
    788         average = pybamm.Integral(child, x) / pybamm.Integral(v, x)
--> 789     return self.process_symbol(average)
    791 elif isinstance(symbol, pybamm.UnaryOperator):
    792     child = symbol.child

File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/discretisations/discretisation.py:730, in Discretisation.process_symbol(self, symbol)
    728     return self._discretised_symbols[symbol]
    729 except KeyError:
--> 730     discretised_symbol = self._process_symbol(symbol)
    731     self._discretised_symbols[symbol] = discretised_symbol
    732     discretised_symbol.test_shape()

File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/discretisations/discretisation.py:765, in Discretisation._process_symbol(self, symbol)
    762 if isinstance(symbol, pybamm.BinaryOperator):
    763     # Pre-process children
    764     left, right = symbol.children
--> 765     disc_left = self.process_symbol(left)
    766     disc_right = self.process_symbol(right)
    767     if symbol.domain == []:

File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/discretisations/discretisation.py:730, in Discretisation.process_symbol(self, symbol)
    728     return self._discretised_symbols[symbol]
    729 except KeyError:
--> 730     discretised_symbol = self._process_symbol(symbol)
    731     self._discretised_symbols[symbol] = discretised_symbol
    732     discretised_symbol.test_shape()

File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/discretisations/discretisation.py:766, in Discretisation._process_symbol(self, symbol)
    764 left, right = symbol.children
    765 disc_left = self.process_symbol(left)
--> 766 disc_right = self.process_symbol(right)
    767 if symbol.domain == []:
    768     return pybamm.simplify_if_constant(
    769         symbol._binary_new_copy(disc_left, disc_right)
    770     )

File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/discretisations/discretisation.py:730, in Discretisation.process_symbol(self, symbol)
    728     return self._discretised_symbols[symbol]
    729 except KeyError:
--> 730     discretised_symbol = self._process_symbol(symbol)
    731     self._discretised_symbols[symbol] = discretised_symbol
    732     discretised_symbol.test_shape()

File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/discretisations/discretisation.py:831, in Discretisation._process_symbol(self, symbol)
    827 elif isinstance(symbol, pybamm.Integral):
    828     integral_spatial_method = self.spatial_methods[
    829         symbol.integration_variable[0].domain[0]
    830     ]
--> 831     out = integral_spatial_method.integral(
    832         child, disc_child, symbol._integration_dimension
    833     )
    834     out.copy_domains(symbol)
    835     return out

File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/spatial_methods/finite_volume.py:209, in FiniteVolume.integral(self, child, discretised_child, integration_dimension)
    207 def integral(self, child, discretised_child, integration_dimension):
    208     """Vector-vector dot product to implement the integral operator."""
--> 209     integration_vector = self.definite_integral_matrix(
    210         child, integration_dimension=integration_dimension
    211     )
    212     out = integration_vector @ discretised_child
    214     return out

File ~/PycharmProjects/PyBaMM-AB/PyBaMM/pybamm/spatial_methods/finite_volume.py:308, in FiniteVolume.definite_integral_matrix(self, child, vector_type, integration_dimension)
    301     matrix = kron(eye(third_dim_repeats), int_matrix)
    302 # print(domain, integration_dimension)
    303 # generate full matrix from the submatrix
    304 # Convert to csr_matrix so that we can take the index (row-slicing), which is
    305 # not supported by the default kron format
    306 # Note that this makes column-slicing inefficient, but this should not be an
    307 # issue
--> 308 return pybamm.Matrix(csr_matrix(matrix))

UnboundLocalError: local variable 'matrix' referenced before assignment`
```
