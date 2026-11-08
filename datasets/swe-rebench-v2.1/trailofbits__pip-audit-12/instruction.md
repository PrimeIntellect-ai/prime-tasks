Design a generic adaptor for Python vulnerability services
Now that we've evaluated osv.dev (#2), we can start designing an abstract interface that individual vulnerability services can satisfy.

From discussion on Slack: we probably want something like this:

```python
class VulnerabilityService(ABC):
    def query(spec: Dependency) -> List[VulnerabilityResult]:
        ...

    def query_all(specs: List[Dependency]) -> Dict[Dependency, List[VulnerabilityResult]]:
        # naive implementation that can be overridden if
        # a particular service supports bulk queries
        [HIDDEN]
```

### Additional contract requirements

- The interface types are importable from the module `pip_audit.service.interface`.
- `VulnerabilityService` declares `query(self, spec: Dependency) -> List[VulnerabilityResult]` and `query_all(self, specs: List[Dependency]) -> Dict[Dependency, List[VulnerabilityResult]]`.
- By default, `query_all` queries each supplied dependency and returns a mapping from that dependency to its results. A service may override this behavior to support bulk queries.
- `Dependency` is constructed as `Dependency(package: str, version: packaging.version.Version)` and exposes the package name as `package` and the version as `version`.
- `VulnerabilityResult` is constructed as `VulnerabilityResult(id: str, description: str, version_introduced: Optional[Version], version_fixed: Optional[Version])`.
