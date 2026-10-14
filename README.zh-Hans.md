# webshot

[English](README.md) · 简体中文

调用 macOS 内置的 WebKit，将本地 HTML 文件渲染为 PNG。

Quick Look 不会执行页面里的 JavaScript，`webshot` 则会在执行完脚本后再截图。运行 `make test` 会依次渲染普通页面、深色模式页面和 JavaScript 动态生成的页面，并校验 PNG 尺寸与抽样像素颜色；包括超时和错误输入在内，全部 13 项检查已在 macOS 27（Apple silicon）上通过。

仅支持 macOS 14 及以上版本。渲染引擎基于 WebKit，输出效果可能与 Chrome 存在差异。页面可使用 Mac 已安装的系统字体及网页自身加载的字体。全程无需浏览器、无需 Node、不开窗口，也不调用系统录屏。

## 编译和使用

安装 Apple Command Line Tools 或自带 Swift 6 及以上版本的 Xcode，然后编译：

```sh
nice -n 10 make
```

```sh
./build/webshot page.html out.png --width 1280 --scale 2 --theme light
```

页面按指定的 CSS 宽度排版，并截取直至 `--max-height` 上限的整页高度，最终输出单张 sRGB 色域的 PNG。

## 选项

| 选项 | 作用 | 默认值 |
| --- | --- | --- |
| `--width px` | 排版宽度（CSS 像素） | `1280` |
| `--scale number` | 每 CSS 像素对应的输出像素倍率 | `2` |
| `--theme light\|dark` | 外观模式（含 `prefers-color-scheme`） | `light` |
| `--wait ms` | 字体与图片加载就绪后的额外等待时间 | `0` |
| `--max-height px` | 最大截取高度（CSS 像素） | `16000` |
| `--clip x,y,w,h` | 截取区域，以文档左上角为原点（CSS 像素） | 整页 |
| `--js "expr"` | 等待结束后执行表达式并打印结果 | 无 |
| `--timeout ms` | 从启动渲染器到写入 PNG 完成的总时限 | `15000` |
| `--help` | 打印用法说明 |  |

输出图像总像素上限为 6400 万，宽度不超过 32768 像素，高度不超过 65536 像素。`--js` 在页面的 JavaScript 上下文中运行，支持等待 Promise；表达式对 DOM 的修改会直接体现在最终截图里。

状态与错误信息输出到 `stderr`，`stdout` 仅用于输出 `--js` 的执行结果和帮助信息。退出码：`0` 表示成功，`1` 表示加载、渲染或写入文件失败，`2` 表示参数错误或输入不可读，`3` 表示超时。即使终端打印了 JavaScript 结果，也不代表后续的 PNG 写入一定成功，请始终以退出码为准。

## 限制

本地资源必须位于 HTML 文件所在目录或其子目录下。外链网络资源能否加载取决于页面本身及当前网络环境。运行时不保留任何浏览器配置。

`webshot` 会等待字体和 HTML 图片加载完成，并要求懒加载的图片立即加载；只要有一张 HTML 图片加载失败，整个任务即告失败。背景图、视频、WebGL、动画以及由定时器延迟触发的任务没有通用的就绪信号，截取这类延迟内容请配合 `--wait` 使用。

截图前，视口高度会拉伸至文档的实际总高度，因此依赖视口高度的布局、`sticky` 元素和 `fixed` 元素的位置可能会随之改变。工具执行的是整页文档渲染，与常规屏幕截图的机制不同。

## 测试

```sh
nice -n 10 make test
```

测试脚本通过 `sips` 读取图像尺寸并裁出单像素样本，再交由一个轻量的 Swift ImageIO 工具校验颜色值；测试用例同时覆盖了区域裁剪、高度上限、小数缩放、参数错误和超时处理。测试生成的图片与日志保存在脚本打印出的临时目录中，可通过环境变量 `WEBSHOT_TEST_TMP` 指定该临时目录的父目录。

## 许可和贡献

采用 MIT 许可证，详见 [LICENSE](LICENSE)。

欢迎提交 issue 和 PR，详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

底层截图调用了 WebKit 的快照接口，渲染视图不挂载到任何窗口。在未登录会话及受限沙盒环境下的兼容性仍有待进一步测试。
