# RanCount 自托管同步

RanCount 沿用 BeeCount Cloud 的账户与账本协议。新增的商家、商品描述、支付渠道和退款关联字段需要配套的 [RanCount Cloud fork 开发分支](https://github.com/iylfei/rancount-cloud/tree/rancount-dev)；旧服务端不会完整保存这些字段。

1. 按 Cloud 仓库的 `docs/DEPLOYMENT.md` 部署其 `rancount-dev` 分支。首次部署可在服务目录运行 `docker compose up -d --build`；升级已有服务前，按其备份说明备份数据库与 `/data` 持久卷，再运行 `alembic upgrade head`。迁移 `0020_rancount_tx_details` 只添加可空交易字段及索引。
2. 用 HTTPS 反向代理公开 API，并检查 `GET /healthz`、`GET /ready`。保存 `/data` 卷及 JWT 密钥；不要在公开配置中写入 API 密钥。
3. 在 RanCount 的现有云服务设置中选择 BeeCount Cloud，填写自建服务的 HTTPS 地址并登录。仅确认入账的记录进入同步；未确认草稿与截图不进入 Cloud。
4. 在“截图记账”设置中单独填写 OpenAI 兼容视觉接口的基础地址、模型和密钥。该配置只保存在本机安全存储中，每台设备需分别设置。

本地 APK 构建使用 `flutter build apk --release --flavor prod`。仓库默认的 Release 签名设置仅适合本地试用；正式分发应配置自己的签名材料，并保存其私钥以便后续升级。

Flutter 工具链固定为 **3.32.8**（见 `.fvmrc`）。Android 默认启用液态玻璃，可在“外观设置”切回经典；“玻璃效果”选择“简化”可降低渲染开销。不支持 shader 折射的设备自动使用简化材质。该选择仅保存在本机，也随配置文件导入导出。


本机有待上传修改时，云端对同一记录的修改或删除会保留为冲突，暂停上传。在云同步页面点击“查看差异”，选择“保留本机”或“使用云端”后继续同步。处理前两份内容都保留在本机；操作期间如果又收到更新，会要求重新查看差异。

账本的月度周期和日统计固定按北京时间划分。关联退款从原支出创建，编辑退款仍保留其关联和负数支出语义；删除原支出前须先处理关联退款。Android 截图、分享和选图产生的记账临时副本在识别完成或会话退出后清理，异常退出遗留副本在下次启动清理，用户相册原图不删除。
