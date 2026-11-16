Exception when using MaterialBalanceType.componentPhase for Flash
When using Coolprop property block with Flash unit operation, the material balance type component phase gives an exception. I am using idaes v2.4.0 . Using the default material balance works fine. The following code can be used to generate the issue

```
from enum import Enum
from pyomo.environ import units as pyunits

from idaes.core import Component, LiquidPhase, VaporPhase, MaterialBalanceType
from idaes.models.properties.modular_properties.coolprop import CoolPropWrapper
from idaes.models.properties.modular_properties.eos.ceos import Cubic, CubicType as CT
from idaes.models.properties.modular_properties.eos.ideal import Ideal
from idaes.models.properties.modular_properties.phase_equil import SmoothVLE
from idaes.models.properties.modular_properties.phase_equil.bubble_dew import IdealBubbleDew, LogBubbleDew
from idaes.models.properties.modular_properties.phase_equil.forms import fugacity
from idaes.models.properties.modular_properties.state_definitions import FTPx
from idaes.core import FlowsheetBlock, PhaseType
from idaes.models.properties.modular_properties.base.generic_property import GenericParameterBlock

from idaes.models.unit_models.flash import Flash
# noinspection PyUnresolvedReferences
from idaes.core.util.model_statistics import degrees_of_freedom

from pyomo.environ import ConcreteModel, SolverFactory


class EosType(Enum):
    """
    Enum for supported EOS types.
    """

    Ideal = 1
    Cubic = 2


class BubbleDewType(Enum):
    """
    Enum for supported Bubble-Dew types.
    """

    IdealBubbleDew = 1
    LogBubbleDew = 2


class CubicType(Enum):
    """
    Enum for supported Cubic EOS types.
    """

    PR = 1
    SRK = 2


class PropertyConfig:

    @staticmethod
    def build_config(eos_type, cubic_type, bubble_dew_type, valid_phases, component_list, phase_list):

        phases = {}
        if "Liq" in valid_phases:
            phases['Liq'] = {
                "type": LiquidPhase,
                "equation_of_state": Ideal if eos_type == EosType.Ideal else Cubic,
                "equation_of_state_options": {"type": CT.PR if cubic_type == CubicType.PR else CT.SRK},
            }
        if "Vap" in valid_phases:
            phases['Vap'] = {
                "type": VaporPhase,
                "equation_of_state": Ideal if eos_type == EosType.Ideal else Cubic,
                "equation_of_state_options": {"type": CT.PR if cubic_type == CubicType.PR else CT.SRK},
            }

        if "Vap" and "Liq" in phases:
            equilibrium_phases = [("Vap", "Liq")]
            phase_equilibrium_state = {("Vap", "Liq"): SmoothVLE}
        else:
            equilibrium_phases = []
            phase_equilibrium_state = {}

        pp = CoolPropWrapper
        components = {cmp: PropertyConfig._build_component(pp, phase_list[cmp]) for cmp in component_list}

        return {
            "components": components,
            # Specifying phases
            "phases": phases,
            # Set base units of measurement
            "base_units": {
                "time": pyunits.s,
                "length": pyunits.m,
                "mass": pyunits.kg,
                "amount": pyunits.mol,
                "temperature": pyunits.K,
            },
            # Specifying state definition
            "state_definition": FTPx,
            "state_bounds": {
                "flow_mol": (0, 100, 1000, pyunits.mol / pyunits.s),
                "temperature": (100.15, 300, 1200, pyunits.K),
                "pressure": (5e4, 1e5, 5e6, pyunits.Pa),
            },
            "pressure_ref": (101325, pyunits.Pa),
            "temperature_ref": (298.15, pyunits.K),
            "phases_in_equilibrium": equilibrium_phases,
            "phase_equilibrium_state": phase_equilibrium_state,
            "bubble_dew_method": IdealBubbleDew if bubble_dew_type == BubbleDewType.IdealBubbleDew else LogBubbleDew,
            "parameter_data": {
                'PR_kappa': PropertyConfig._builtkij(component_list),
            },
        }

    @staticmethod
    def _build_component(pp, valid_phases):
        return {
            "type": Component,
            "dens_mol_liq_comp": pp,
            "enth_mol_liq_comp": pp,
            "enth_mol_ig_comp": pp,
            "entr_mol_liq_comp": pp,
            "entr_mol_ig_comp": pp,
            "pressure_sat_comp": pp,
            "valid_phase_types": valid_phases,
            "phase_equilibrium_form": {("Vap", "Liq"): fugacity},
            "parameter_data": {
                "mw": pp,
                "dens_mol_crit": pp,
                "pressure_crit": pp,
                "temperature_crit": pp,
                "omega": pp,
            }
        }

    # Build the kij parameters:
    @staticmethod
    def _builtkij(component_list):
        result_dict = {}
        for i in range(len(component_list)):
            for j in range(len(component_list)):
                key = (component_list[i], component_list[j])
                result_dict[key] = 0.000
        return result_dict
"""
Define the component list and property pack options for the application.
There is one global component list per application. We can have several
property packages within a single application each with different property
options and phase lists.
"""

component_list = [
    "Hydrogen",
    "Water",
    "CarbonDioxide",
    "HydrogenSulfide",
    "Methanol",
    "Methane",
    "Ethane",
    "Ethylene",
    "Propane",
    "n-Butane",
    "IsoButane",
    "Isopentane",
    "n-Pentane",
    "n-Hexane",
    "n-Heptane",
    "n-Octane",
    "n-Nonane"
]

phase_list = {
    "Hydrogen": [PhaseType.vaporPhase],
    "Water": [PhaseType.vaporPhase, PhaseType.liquidPhase],
    "CarbonDioxide": [PhaseType.vaporPhase, PhaseType.liquidPhase],
    "HydrogenSulfide": [PhaseType.vaporPhase, PhaseType.liquidPhase],
    "Methanol": [PhaseType.vaporPhase, PhaseType.liquidPhase],
    "Methane": [PhaseType.vaporPhase, PhaseType.liquidPhase],
    "Ethane": [PhaseType.vaporPhase, PhaseType.liquidPhase],
    "Ethylene": [PhaseType.vaporPhase, PhaseType.liquidPhase],
    "Propane": [PhaseType.vaporPhase, PhaseType.liquidPhase],
    "n-Butane": [PhaseType.vaporPhase, PhaseType.liquidPhase],
    "IsoButane": [PhaseType.vaporPhase, PhaseType.liquidPhase],
    "Isopentane": [PhaseType.vaporPhase, PhaseType.liquidPhase],
    "n-Pentane": [PhaseType.vaporPhase, PhaseType.liquidPhase],
    "n-Hexane": [PhaseType.vaporPhase, PhaseType.liquidPhase],
    "n-Heptane": [PhaseType.vaporPhase, PhaseType.liquidPhase],
    "n-Octane": [PhaseType.vaporPhase, PhaseType.liquidPhase],
    "n-Nonane": [PhaseType.vaporPhase, PhaseType.liquidPhase],
}


def build_model_with_property_package():
    m = ConcreteModel()
    m.fs = FlowsheetBlock(dynamic=False)
    configuration = PropertyConfig.build_config(
        eos_type=EosType.Cubic,
        cubic_type=CubicType.PR,
        bubble_dew_type=BubbleDewType.IdealBubbleDew,
        valid_phases=["Vap", "Liq"],
        component_list=component_list,
        phase_list=phase_list
    )
    m.fs.props = GenericParameterBlock(**configuration)

    return m


def build_flow_sheet(m):
    m.fs.flash = Flash(property_package=m.fs.props, material_balance_type=MaterialBalanceType.componentPhase)

    return m


def initialize(m, T, P):
    # Fix state for initialization
    m.fs.flash.inlet.flow_mol.fix(1)
    m.fs.flash.inlet.temperature.fix(T)
    m.fs.flash.inlet.pressure.fix(P)
    for _component in component_list:
        m.fs.flash.inlet.mole_frac_comp[0, _component].fix(1 / len(component_list))

    m.fs.flash.heat_duty.fix(0.)
    m.fs.flash.deltaP.fix(0.)

    m.fs.flash.initialize()

    return m


def solve_model(m):

    m.fs.flash.inlet.temperature.unfix()
    m.fs.flash.control_volume.properties_out[0].mole_frac_phase_comp['Vap','Propane'].fix(0.08)

    opt = SolverFactory("ipopt")
    solve_status = opt.solve(m, tee=True)

    return m, solve_status


m = build_model_with_property_package()
m = build_flow_sheet(m)
#m = initialize(m, T=387.0, P=1201325.0)
# m, status = solve_model(m)

m.fs.flash.report()

```

### Additional contract requirements

- `GenericParameterBlock` (in module `idaes.models.properties.modular_properties.base.generic_property`) exposes a `phase_equilibrium_list` attribute. Each entry maps a phase-equilibrium index (for example `"PE1"`) to a list of the form `[component_name, (phase_1, phase_2)]`, where `component_name` is the name of the component in equilibrium and `(phase_1, phase_2)` is the ordered pair of phases in equilibrium.


- For the benzene/toluene Vapor-Liquid equilibrium case, `phase_equilibrium_list` must equal `{"PE1": ["benzene", ("Vap", "Liq")], "PE2": ["toluene", ("Vap", "Liq")]}`.
