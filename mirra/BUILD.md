# 本机测试客户端构建

这些脚本保存已验证构建步骤，不是依赖自动安装器。支持本次验收环境：Apple Silicon macOS、Command Line Tools、Rosetta 2。完整原生从源码构建或不同平台请使用上游构建流程并重新验收。

## 固定版本与目录

- RustDesk 1.5.0：`fada664df7a294d1d1a9ca3e7cd3637069122f17`
- Rust 1.81.0；Flutter 3.24.5 / Dart 3.5.4
- flutter_rust_bridge_codegen 1.80.1；codegen 的独立 Dart 环境依赖 ffi 2.0.2、ffigen 8.0.2
- hbb_common 子模块：`229b904508364c8997aad0fb5af57effac859f60`
- vcpkg：`9e593bb18ea69cc5095e012465dcd675a822ed0d`，按上游 manifest 安装 arm64-osx 依赖
- 本次辅助工具：NASM 2.16.03、pkgconf 2.3.0

运行 `git submodule update --init --recursive`。准备默认的 `mirra/workspace/` 或将 `MIRRA_WORKSPACE` 设置为已有独立开发目录，该目录应包含：

```text
toolchain/cargo/bin/                 # rustup/cargo/codegen
toolchain/rustup/                    # Rust 1.81.0
toolchain/flutter/                   # Flutter 3.24.5
toolchain/pub-cache/
toolchain/vcpkg/
toolchain/native-tools/bin/          # pkg-config、nasm 等
toolchain/bridge-dart/pubspec.yaml    # ffi、ffigen 独立环境
native/arm64-osx/                    # vcpkg 依赖产物
```

本机曾使用 `build-helpers/cidre-xcodebuild.py` 适配 cidre pomace 的 macOS arm64 静态库编译，可复制到独立 `native-tools/bin/xcodebuild` 并赋予执行权限。它只接受指定目标，不替代完整 Xcode；不要覆盖系统工具。完整 Xcode 环境可使用原工具。

## 编译、测试、打包

以下命令在仓库根目录执行。首次准备需要生成匹配的 Flutter/Rust 桥接代码，再构建核心与界面：

```sh
./mirra/generate-bridge.sh
./mirra/build-core.sh
./mirra/build-ui.sh
./mirra/test-routing.sh
./mirra/test-ui.sh
python3 mirra/package-test-app.py --with-ui
```

核心编译设置 `MIRRA_TEST_APP=1`；UI 设置 `MIRRA_ROUTING_UI=true`。生成文件遵循原仓库忽略规则，不提交生成桥接或二进制。

打包需要已安装匹配的 `/Applications/RustDesk.app` 1.5.0；脚本校验版本与导出符号，复制原生程序/窗口/插件、替换核心与 Flutter 框架、删除系统服务程序并重新签名。输出位于 `$MIRRA_WORKSPACE/dist/`（没有设置变量时位于 `mirra/workspace/dist/`）。打包复用原生组件，并非完整原生应用从零编译。替换已有测试包之前必须先关闭它，之后使用 `--replace --with-ui`。

## 可选验收

真实查询只读取服务状态，需要两台美国与两台中国设备 ID，顺序固定。ID 只在本机环境变量传入，源码没有设备清单：

```sh
MIRRA_LIVE_TEST_IDS="<美国ID1>,<美国ID2>,<中国ID1>,<中国ID2>" ./mirra/test-routing.sh --ignored
```

可选的 `python3 mirra/prepare-test-profile.py` 只在测试配置目录不存在时从本机原版配置导入服务器设置和指定服务的普通数字 ID 收藏。它不复制 Account token，不设置本机永久密码。登录和永久密码均通过测试应用原界面完成；运行脚本前可先按实际需要检查导入范围。

不要提交工作目录、应用包、机器配置、访问 token、私钥、日志或截图。上游升级必须重新核对桥接、原生组件、四个代码接入点和锁文件，随后重跑测试及真实连接。
