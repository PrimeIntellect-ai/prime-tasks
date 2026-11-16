【Progress】测试覆盖率提升
> 目前正在推进 mobile-vue 的组件测试覆盖率提升。

## 任务要求
- **行覆盖率达 80%+**
- **分支覆盖率 80%+**
- **语句覆盖率 80%+**
- 有交互的组件，需要覆盖所有场景，**要求函数覆盖率 80+%**

## 单元测试指引
 [mobile-vue 的单元测试指引文档](https://github.com/Tencent/tdesign-mobile-vue/wiki/mobile-vue%EF%BC%9A%E5%8D%95%E5%85%83%E6%B5%8B%E8%AF%95%E6%8C%87%E5%BC%95)

> **目前每个组件都拥有自己的测试用例文件，我们可以先通过`npm run test:unit-coverage`生成测试覆盖率报告，查看该组件的单元测试覆盖率情况，然后针对性的补充测试用例**

#### Tips
- Vitest 单元测试框架：[文档](https://cn.vitest.dev/guide/)
- 若开发工具为 vscode ，可以安装 Vitest 插件

## 激励

参与共建的开发者，将可以获得 [TDesign 周边](https://github.com/Tencent/tdesign/wiki/TDesign-%E5%91%A8%E8%BE%B9)（贴纸、鼠标垫、工卡套等）；

成为核心贡献者，将会拥有 TDesign 专属头像。

## IssueShoot
- 预估时长: 1
- 期望完成时间: 2023-05-29 00:00:00 +0000 UTC
- 开发难度: 低
- 参与人数: 1
- 验收标准: 实现期望改造效果，提 PR 并通过验收无误
- 备注: 最终激励以实际提交 `pull request` 并合并为准

### Additional contract requirements

The `Progress` component is exported from `src/progress/progress.vue` (and as the `Progress` component of the library). It renders a root element with the class `t-progress`, and its appearance is driven by props:

- `status`: one of `'' | 'success' | 'error' | 'warning' | 'active'`. The rendered status modifier class is `t-progress--status-<status>`, where an empty `status` maps to `default` (for example `t-progress--status-default` and `t-progress--status-success`).
- `theme`: one of `'line'` (default), `'plump'` and `'circle'`. For the `plump` theme the rendered bar element carries the class `t-progress--plump`. When `theme` is empty, the component renders no text content.
- `percentage`: sets the width of the inner bar (for example `percentage=50` renders an inner bar with width `50%`).
- `strokeWidth`: sets the height of the progress track (for example `strokeWidth=10` renders a track of height `10px`).
