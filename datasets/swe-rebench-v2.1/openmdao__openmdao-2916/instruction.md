Bogus error raised when calling promotes on a deeply nested output to address conflicting output names.
### Description

When we have 2 identical output names that are promoted with wildcards into a subsystem where they collide, we can call `promotes` to set one of them.  This works if we call promotes on higher level groups, but not at the the deepest level. It should work at all levels (though the tradeoff will be increased setup time.)

### Example

```python
import openmdao.api as om


class FuselageParameters(om.ExplicitComponent):
    def setup(self):
        self.add_output('avg_diam', val=0)


class FuselageGroup(om.Group):
    def setup(self):
        parameters = self.add_subsystem(
            "parameters",
            FuselageParameters(),
            promotes_outputs=["*"],
        )


class SizeGroup(om.Group):
    def setup(self):
        self.add_subsystem(
            "fuselage",
            FuselageGroup(),
            promotes_outputs=["*"],
        )


class StaticAnalysisGroup(om.Group):

    def setup(self):

        self.add_subsystem("gasp", SizeGroup(),
            promotes_outputs=["*"],
        )

        self.add_subsystem('flops', SizeGroup(),
            promotes_outputs=['*']
        )

    def configure(self):
        outs = [('avg_diam', 'MANUAL_OVERRIDE:avg_diam')]

        # Caches an error that is bogus.
        self.gasp.fuselage.promotes('parameters', outputs=outs)

        # Works
        #self.gasp.promotes('fuselage', outputs=outs)

        # Works
        #self.promotes('gasp', outputs=outs)


prob = om.Problem()

prob.model.add_subsystem('static_analysis', StaticAnalysisGroup(),
                         promotes_outputs=['*'])

prob.setup()
```


### OpenMDAO Version

3.26.1-dev

### Relevant environment information

_No response_
