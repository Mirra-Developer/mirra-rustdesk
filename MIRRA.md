# Mirra RustDesk Test

基于 RustDesk 1.5.0 的独立 macOS 测试客户端。官方上游：<https://github.com/rustdesk/rustdesk>。本分支 `mirra-routing` 保存 Mirra 定制功能，上游许可证及历史保留。

## 功能

Settings 在 Network 和 Display 之间增加“连接路由”，原 Network、Display 和 Account 页面保留。支持多个可信 ID 服务，并为普通数字设备 ID 选择自动查询归属或固定服务；保留 Account 登录、地址簿及设备密码验证。每次连接持有独立服务器、公钥和账号凭证，不修改全局 ID 服务。

“自动”是查询设备注册在哪个 ID 服务，不是比较服务器响应速度。远端仍按原流程注册；本机全局 Network 设置仍负责本机被连接时的注册。新功能只改变控制端主动连接的选择流程，不增加服务端强制账号策略。

默认中美服务参数在 `src/auto_id_config.rs`；服务器公钥是公开信息。运行时可通过页面编辑服务。当前账号 API 保持 Mirra 原服务，本仓库不包含账号、密码、访问 token、设备清单或运行日志。

## 文档与构建

- [使用、配置、隔离与升级说明](mirra/CONNECTION_ROUTING.md)
- [固定依赖与构建步骤](mirra/BUILD.md)
- 脚本：`mirra/`；新增核心：`src/auto_id*.rs`；新增 UI：`flutter/lib/desktop/connection_routing/`。

已在 Apple Silicon Mac 验证中国/美国各两台设备的自动及手动并发连接、配置保存和重启恢复。9 项 Rust 测试、3 项 Flutter 配置测试通过。未提供通用 CI 构建保证；本机测试包复用原版 1.5.0 匹配的原生窗口和插件，重新编译 Rust 核心及 Flutter 界面。

测试包采用独立标识 `com.mirra.rustdesk.test`，配置/IPC 与正式应用隔离。上游升级后应先合并代码并重新测试，不能直接覆盖定制应用。
