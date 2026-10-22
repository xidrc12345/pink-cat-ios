# 构建与验证

## 已实际使用的环境

- 64 位 Windows，Python 3.12。
- llvm-mingw `20250613`，clang/LLD 20.1.7。
- 不依赖 Xcode 或第三方 dylib。没有从仓库里捆绑编译器或 SDK。

## 安装依赖（手动执行）

已有 Python / LLVM 时可跳过。下载命令仅准备工具，不注入设备、不安装服务。

```powershell
winget install --id Python.Python.3.12 -e
New-Item -ItemType Directory -Path tools -Force | Out-Null
$url = 'https://github.com/mstorsjo/llvm-mingw/releases/download/20250613/llvm-mingw-20250613-ucrt-x86_64.zip'
Invoke-WebRequest -Uri $url -OutFile tools/llvm.zip
if ((Get-FileHash tools/llvm.zip -Algorithm SHA256).Hash.ToLowerInvariant() -ne '45145c035d9246e1de16f1873aa9afa863d93909f4a8f363e2eb38a04031d3c3') { throw 'Toolchain checksum mismatch' }
Expand-Archive -LiteralPath tools/llvm.zip -DestinationPath tools
$llvm = (Resolve-Path tools/llvm-mingw-20250613-ucrt-x86_64/bin).Path
```

## 构建

在仓库根目录运行，或将文件名替换为你解压后对应的完整路径：

```powershell
python build.py --llvm-bin "$llvm"
python run_tests.py --llvm-bin "$llvm"
python validate_source.py
python verify_macho.py build/PinkCatAudio.dylib --out build/macho-validation.json
```

产物是 `build/PinkCatAudio.dylib`。编译和链接日志在 `build/`，测试 JSON 在 `build/tests.json`。

`build.py` 优先使用 `ld64.lld`；不存在时使用 `ld.lld -flavor darwin`。LLVM 必须包含 Mach-O 链接功能。不能使用 PE 链接结果更名为 dylib。

`build.py` 使用公共 ABI 声明和最小链接 stub，目标库运行时从宿主已加载的 Foundation/UIKit/Objective-C 解析符号。编译通过不证明这些符号在目标设备可用；真机加载是独立验收项。

`run_tests.py` 当前是 **Windows x64 主机模拟测试**，不是 iOS 模拟器。它执行真实的策略/原生控制源码，Mach/Opus 被替身提供，字符串格式化由主机 CRT 提供。布局边界断言不验证 UIKit 字形宽度或点击分发。

## 真机验收清单（本次未执行）

1. 移除旧注入库，再加载当前库，确认默认只出现一个 `pink cat`。
2. 面板收起/展开、拖动、关闭、两档选择和两次复制都能触发。
3. 小屏/横屏可滚动到联系方式，顶部关闭键始终可见；刘海/底部安全区无溢出。
4. 上麦前发送显示 `--`；上麦后用实时统计而非目标值判断。下麦、统计过期后不会继续展示旧发送值。
5. 验证参数确认前显示“等待生效”或“CBR 未确认”，确认后才显示 Opus CBR。
6. 选择恢复原版后下麦再上麦，接收方仍能正常听到。重新打开 TT 仍记住选择。
7. 测试接收端听感、后台/前台、反复上麦和长时间使用。不以 SDK 返回成功替代听感验收。

不匹配版本下应显示兼容性提示，不应修改未知原生布局。出现问题先恢复原版；必要时移除注入库并重启。
