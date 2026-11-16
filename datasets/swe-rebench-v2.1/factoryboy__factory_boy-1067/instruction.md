KeyError: 'locale'
#### Description
KeyError: 'locale' generated when calling Faker.
factory/faker.py:46: KeyError
Seems that the `extra` dictionary is empty, but `locale` key is expected.

#### To Reproduce
running unit test with tox
python 3.10; factory-boy==3.2.1 faker==13.15.0

##### Model / Factory code
```python
@pytest.fixture
def unique_dominant_factors():
  return list(set(DominantFactorsFactory.create_batch(3)))

@pytest.fixture
def portfolio_values_per_dominant_factors(unique_dominant_factors):
    scenario_ids = np.array([3, 4, 5, 6, 7, 8, 9, 10])
    portfolio_values_per_dominant_factors = PortfolioValuesPerDominantFactors(
        scenario_ids=scenario_ids, dominant_factors=unique_dominant_factors
    )
    rng = np.random.default_rng(seed=2021)
    for i in range(len(unique_dominant_factors) - 1):
        portfolio_values_per_dominant_factors.add_instrument_values_by_factor_name(
            unique_dominant_factors[i], rng.normal(size=8)
        )
    portfolio_values_per_dominant_factors.add_instrument_values_by_factor_name(
        unique_dominant_factors[-1], np.zeros(8)  # Portfolio value 0 can also occur
    )

    return portfolio_values_per_dominant_factors
```

##### The issue
*Add a short description along with your code*

```python

    @pytest.fixture
    def unique_dominant_factors():
>       return list(set(DominantFactorsFactory.create_batch(3)))

tests/repositories/test_portfolio_values_per_dominant_factors_repository.py:14:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
.tox/py3/lib/python3.10/site-packages/factory/base.py:540: in create_batch
    return [cls.create(**kwargs) for _ in range(size)]
.tox/py3/lib/python3.10/site-packages/factory/base.py:540: in <listcomp>
    return [cls.create(**kwargs) for _ in range(size)]
.tox/py3/lib/python3.10/site-packages/factory/base.py:528: in create
    return cls._generate(enums.CREATE_STRATEGY, kwargs)
.tox/py3/lib/python3.10/site-packages/factory/base.py:465: in _generate
    return step.build()
.tox/py3/lib/python3.10/site-packages/factory/builder.py:258: in build
    step.resolve(pre)
.tox/py3/lib/python3.10/site-packages/factory/builder.py:199: in resolve
    self.attributes[field_name] = getattr(self.stub, field_name)
.tox/py3/lib/python3.10/site-packages/factory/builder.py:344: in __getattr__
    value = value.evaluate_pre(
.tox/py3/lib/python3.10/site-packages/factory/declarations.py:477: in evaluate_pre
    [HIDDEN]
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

self = <factory.faker.Faker object at 0x7f3843200df0>
instance = <Resolver for <BuildStep for <StepBuilder(<FactoryOptions for DominantFactorsFactory>, strategy='create')>>>
step = <BuildStep for <StepBuilder(<FactoryOptions for DominantFactorsFactory>, strategy='create')>>, extra = {}

    def evaluate(self, instance, step, extra):
>       locale = extra.pop('locale')
E       KeyError: 'locale'


```

#### Notes
Factory-boy version 3.0.1 works properly

### Additional contract requirements

- Evaluating a Faker declaration without a supplied locale must not raise `KeyError: 'locale'`.
