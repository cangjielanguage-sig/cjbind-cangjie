# cjbind

## 依赖版本

- 仓颉内核版本：`1.1.0-alpha.41` 或者ohos版本：`1.1.0-alpha.36` 
- uv: `>= 0.6.0` Python 版本：`>= 3.11`：用于运行 `scripts` 下的脚本并自动配置依赖
- Go: `>= 1.24`：用于构建 opt 的补丁

## 拉取最新的 `libclang` 预编译包

此程序依赖于 `libclang`，请确保你的系统中安装了 `llvm`。

当前 `cjbind` 使用 `qt` 提供的预编译 `libclang`。使用以下命令下载 `libclang`：

```
uv run scripts/download.py
```

## 安装 gcc 环境

windows 平台还需要通过 MSYS2 安装 mingw-w64-x86_64-gcc 编译器。

## 构建

因为仓颉当前不支持在 `build.cj` 中设置 `link-options`, 因此编译时需要设置环境变量来完成链接。

使用 `scripts/cjpm.py` 来自动设置环境变量。

```
uv run scripts/cjpm.py build -V
```

## 生成 libclang 绑定

假设 `libclang` 的头文件在 `T:\cjbind-bootstrap\include\clang-c\Index.h`，可以使用以下命令生成 `libclang.cj`：

```
cjbind -o libclang.cj -p cjbind.clang T:\cjbind-bootstrap\include\clang-c\Index.h -- -I T:\cjbind-bootstrap\include\
```