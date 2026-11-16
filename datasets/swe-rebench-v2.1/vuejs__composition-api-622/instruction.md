beta22, the useCssModule did'nt adapt the change of getCurrentInstance.
vue version: 2.6.12
@vuejs/composition-api version: 1.0.0-beta.22

beta22, the `useCssModule` did'nt adapt the change of `getCurrentInstance`.
https://github.com/vuejs/composition-api/blob/4b2f1ab9405462da163089616829046b72d86dcb/src/apis/useCssModule.ts#L8-L23

```TypeScript
export const useCSSModule = (name = '$style'): Record<string, string> => {
  const instance = getCurrentInstance()
  if (!instance) {
    __DEV__ && warn(`useCSSModule must be called inside setup()`)
    return EMPTY_OBJ
  }

  [HIDDEN]
  if (!mod) {
    __DEV__ &&
      warn(`Current instance does not have CSS module named "${name}".`)
    return EMPTY_OBJ
  }

  return mod as Record<string, string>
}
```
![image](https://user-images.githubusercontent.com/35187547/103393216-8e375f00-4b5c-11eb-923b-3f4b1c2b50b1.png)

### Additional contract requirements

- During setup, `useCSSModule(name)` must return the CSS module associated with the current component under `name`; when `name` is omitted, it defaults to `$style`. This behavior must work with the beta.22 `getCurrentInstance` behavior.
