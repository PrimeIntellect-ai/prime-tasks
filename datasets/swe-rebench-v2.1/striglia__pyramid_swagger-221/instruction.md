Improve how pyramid_swagger builds bravado-core configs
The current implementation of [``create_bravado_core_config``](https://github.com/striglia/pyramid_swagger/blob/c97c227f2a103b73fbf72906cac977df114ad622/pyramid_swagger/ingest.py#L188) limits the bravado-core configurations that could be set. The project already had some issues asking to expose new bravado-core configs through pyramid_swagger configs (ie. #211).

I'm wondering if we could actually have a passthrough prefix for setting bravado-core configs.
The idea is to use all the pyramid_swagger configs that starts with a given prefix as bravado-core configs like ``bravado_core.XXX: 1`` will set bravado-core config XXX to 1
