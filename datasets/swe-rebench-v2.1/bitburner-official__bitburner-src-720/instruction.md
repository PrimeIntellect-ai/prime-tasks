Obsolete?/changed? ns functions results in ns.getFunctionRamCost Runtime Errors
Iterate through ns objects, identify those that are functions and call getFunctionRamCost on each.

Runtime Errors:
1. Invalid function passed to getRamCost: getServerRam
2. Invalid function passed to getRamCost: singularity.getAugmentationCost
3. Invalid function passed to getRamCost: sleeve.getSleeveStats
4. Invalid function passed to getRamCost: sleeve.getInformation
5. Invalid function passed to getRamCost: corporation.assignJob
6. Invalid function passed to getRamCost: corporation.getEmployee
7. Invalid function passed to getRamCost: corporation.getExpandCityCost
8. Invalid function passed to getRamCost: corporation.getExpandIndustryCost
9. Invalid function passed to getRamCost: corporation.getIndustryTypes
10. Invalid function passed to getRamCost: corporation.getMaterialNames
11. Invalid function passed to getRamCost: corporation.getPurchaseWarehouseCost
12. Invalid function passed to getRamCost: corporation.getResearchNames
13. Invalid function passed to getRamCost: corporation.getUnlockables
14. Invalid function passed to getRamCost: corporation.getUpgradeNames
15. Invalid function passed to getRamCost: formulas.work.classGains

### Additional contract requirements

- Add a public function `getRamCost(tree: string[], throwOnUndefined?: boolean): number` in module `src/Netscript/RamCostGenerator.ts`. It returns the RAM cost for the Netscript function at the given namespace path. When the path has no defined RAM cost (for example a removed function), it returns `0`; when `throwOnUndefined` is `true` it throws instead.
- `ns.getFunctionRamCost(name: string): number` returns the RAM cost for the function named by `name`, where `name` is a dot-separated namespace path.
