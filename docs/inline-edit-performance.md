# 文案拆分／合并性能记录

2026-10-09，同一台机器、同一份隔离数据、Release 构建。数据包含 300 条长短混合文案、重复文本、100 个图片绑定、300 条备注和 30 个动画任务。没有修改版本号、打包或发布 Git。

## 本次实现

- 一次建立旧行到新行的迁移映射，复用未变文本的 hash，合并元数据与素材索引更新，动画任务不再逐任务扫描全文。
- 派生统计和筛选属性统一缓存，结构编辑结束时统一失效。草稿由独立编辑会话持有，普通输入由编辑器订阅。
- 内部 UUID 维持原生列表和编辑器身份；磁盘上的文本 hash／重复序号 ID 不变。同步更新仍持有焦点的编辑器及光标，操作标识排除失效的编辑／滚动请求。
- 缓存文本高度和有效的原生滚动视图。目标光标可见时保持阅读位置，否则最小距离滚动。保留原有进入、拆分和合并反馈动效。
- 主线程捕获不可变快照，串行后台队列更新偏好、构造 manifest、编码和写盘。保留 120 毫秒合并保存；撤销、同步持久化、切项目和退出前排空队列。

## 实际窗口结果

时间从 NSTextView 收到键盘事件起，到目标编辑器已经同步文本／光标且成为 first responder 为止；包括同步模型更新，不包含动画完成时间。P95 使用线性插值。每次操作之间读取原生窗口可访问性状态；该读取会产生额外 AX 工作，数值不等同于完全无人操作的性能。

| 30 次窗口操作 | 优化前 | 优化后 |
| --- | ---: | ---: |
| 输入就绪中位数 | 325.82 ms | 60.45 ms |
| 输入就绪 P95 | 391.71 ms | 68.42 ms |
| 模型更新 P95 | 27.53 ms | 24.98 ms |
| 拆分输入就绪 P95（15 次） | 412.04 ms | 120.56 ms |
| 合并输入就绪 P95（15 次） | 310.80 ms | 63.40 ms |
| 最慢输入就绪 | 422.46 ms | 240.31 ms |

优化后第一次拆分耗时 240.31 ms，其余 29 次均低于 100 ms。再连续发送 15 组 Enter／Backspace，中间不读取 AX 状态，30 次均完成：拆分最大 68.17 ms，合并最大 60.10 ms；最终焦点仍在正确编辑器。

**尚不能宣布完整验收通过。** 总体样本达到 P95 ≤100 ms，但首次拆分仍有慢样本，单独 15 次拆分的 P95 未达门槛，且本次窗口循环集中于同一可见行。需要补充不同位置、首次进入编辑及真实中文输入法的测量。首次原生编辑器挂载仍可能等待列表插入过程；这是生命周期观察得出的判断，尚无干净的 trace 能独立量化其占比。

120 次独立模型操作（`swiftc -O`）P95：优化前 1.43 ms，优化后 1.48 ms。这份数据未显示模型纯计算提速；当前窗口改善主要来自编辑器身份、焦点恢复和列表刷新范围变化。不要将窗口与独立模型的数值混为一类。

## 回归与证据边界

- Release 构建成功；inline/auxiliary、production methods、shooting devices、distribution、filter、timeline、script import、animation 现有测试及新增优化／性能测试通过。
- 新增测试覆盖重复文本迁移、编辑器显示身份、明确未设置设备、缓存一致失效、Unicode、撤销／重做、异步保存结果与原 manifest 逐字节一致、队列覆盖和写入失败。
- 实际窗口验证了拆分／合并、空条目、连续按键、撤销／重做、筛选和独立时间线窗口。退出后核对原文完全一致，仍有 300 条备注、100 个绑定和 30 个动画任务。项目切换保存由现有模型测试覆盖，未额外做窗口切项目测试。
- 中文输入法组合输入、实际选区拆分、所有离屏位置以及待保存时立即退出，尚未完成专门的窗口验证。模型层 Unicode／选区边界与退出排空机制不能替代这些验证。
- 已录制优化前后 Time Profiler 和 Animation Hitches。AX 树查询占用大量样本，当前 trace 不能证明纯应用热点或无动画卡顿；优化后 Hitches 录制主要覆盖窗口／筛选操作，仍需专门录制拆分／合并。

本地原始测量、Release 构建、日志和 trace 位于 `/tmp/broll-inline-perf/`，属于临时诊断数据。trace 可能包含环境信息，不应直接公开。

## 复现

```sh
Tests/run-inline-optimization-tests.sh
Tests/run-inline-performance-tests.sh
Tests/run-inline-performance-tests.sh --prepare /tmp/broll-inline-verification
```

启动新 Release 可执行文件时设置 `BROLL_DESK_VERIFICATION_DIRECTORY=/tmp/broll-inline-verification`，再在应用内选择该目录下的 `project`。设置 `BROLL_DESK_INLINE_METRICS=/tmp/inline-metrics.jsonl` 可保存数字计时；默认不写日志。日志仅记录操作类型和耗时，不记录文案／素材路径。

Instruments 的 Points of Interest 区间：`InlineKeyToFocus`、`InlineModelUpdate`、`InlineSavePreparation`、`InlineSaveWrite`。准备区间包括偏好更新、manifest 构造和编码；写盘单独记录。它们不会将动画结束冒充输入就绪。
