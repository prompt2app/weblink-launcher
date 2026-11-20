# 网页快开 (weblink-launcher)

在 macOS 上用 Spotlight 快速打开常用网址：输入名称开头几个字，回车，网址就在浏览器里打开。体验接近 Alfred / uTools 的「网页快开」，但不需要常驻任何第三方启动器。

## 功能

- 按 `⌘ 空格` 输入名称回车，就能打开对应网址，用的是系统自带的 Spotlight，不用额外装启动器
- 每个网址都有自己的图标，在 Spotlight 里一眼就能认出来
- 有图形化管理器，可以添加、编辑、删除、排序网址
- 自动抓取网站图标；网站图标太小时，用网站主色生成文字图标
- 提供命令行，方便批量导入，比如从 uTools「网页快开」迁移过来
- 只有一个 Swift 源文件，不依赖任何第三方库

## 安装

### 方式一：下载 Release（推荐）

1. 到 [Releases](../../releases) 下载 `网页快开管理-x.y.z.zip`，解压
2. 把 `网页快开管理.app` 放到 `~/Applications/网页快开/`。放到其他位置也能用，但放在这里方便统一管理
3. 首次打开：应用没有 Apple 开发者签名，用的是 ad-hoc 签名，系统会拦截。解决办法任选一种：
   - 在 Finder 里右键点应用，选「打开」，再点「打开」
   - 或者在终端执行：
     ```bash
     xattr -dr com.apple.quarantine ~/Applications/网页快开/网页快开管理.app
     ```

> Release 包是 Apple Silicon（arm64）版本，需要 macOS 14 或更高。Intel Mac 请从源码编译，编译前把 `build.sh` 里的 `-target` 改成 `x86_64-apple-macosx14.0`。

### 方式二：从源码编译

```bash
git clone https://github.com/prompt2app/weblink-launcher.git
cd weblink-launcher
./build.sh
```

## 使用

1. 打开「网页快开管理」，点「添加」，填写名称和网址后保存。图标会自动获取
2. 按 `⌘ 空格`，输入名称（或者开头几个字），回车，浏览器就会打开这个网址
3. 想用缩写打开，比如输入 `txy` 打开腾讯云：把名称改成 `txy 腾讯云` 这种形式

## 卸载

```bash
rm -rf ~/Applications/网页快开 ~/Library/Application\ Support/网页快开
```

## 项目结构

```
main.swift   管理器全部源码：数据存储、图标抓取与绘制、入口生成、SwiftUI 界面、命令行
build.sh     编译、生成应用图标、签名，安装到 ~/Applications/网页快开/
```

## 原理

每个网址都会生成一个很小的 `.app` 启动入口，统一放在 `~/Applications/网页快开/` 下，比如 `Gmail.app`、`腾讯云.app`。Spotlight 会把这些入口当作普通应用来搜，名字完全匹配时排在最前面。

- 每个入口用 `osacompile` 编译，内容只有一句 `open location "<网址>"`，以后台方式运行（`LSUIElement`），不会在 Dock 里闪一下。
- 图标会自动抓取：先找网站的 `apple-touch-icon` 和 `<link rel=icon>`，找不到再用 `/favicon.ico`，选像素最大的一张，放进 macOS 风格的白色圆角方块里。网站图标太小（小于 64px）时，改用「网站主色 + 名称首字」生成文字图标。
- 生成入口时会去掉 `CFBundleIconName`。这一步不能省：留着它，系统会去找 `Assets.car` 里的默认图标，自定义图标就显示不出来。

## 管理器

「网页快开管理.app」是一个 SwiftUI 小应用，可以：

- 添加、编辑、删除网址，改名后会自动替换旧入口
- 自动获取网站图标，也可以选本地图片，或者使用文字图标
- 拖动排序，或者直接点开网址

数据保存在 `~/Library/Application Support/网页快开/`：`links.json` 存网址列表，`icons/` 存渲染好的图标。

## 编译安装

只需要 Xcode Command Line Tools，不用装完整的 Xcode。

```bash
./build.sh
```

脚本会编译生成 `~/Applications/网页快开/网页快开管理.app`。

> 只装了 Command Line Tools 时，SwiftUI 的 `@State` 宏插件用不了，所以代码里的界面状态全部放在 `ObservableObject` 模型里，没有用 `@State`。
>
> `build.sh` 默认编译 Apple Silicon（arm64）版本，最低支持 macOS 14。

## 命令行

```bash
M=~/Applications/网页快开/网页快开管理.app/Contents/MacOS/WebLinkManager

# 添加或更新一个网址，自动抓取图标
"$M" --import "Gmail" "https://mail.google.com/"

# 直接使用一张做好的 1024px 图标
"$M" --import "腾讯云" "https://console.cloud.tencent.com/" /path/to/icon.png

# 提供一张备选原图，和网站图标比较后取更清晰的那张
"$M" --import "Jenkins" "http://jenkins.example.com" src:/path/to/logo.png
```

## 常见问题

- **Spotlight 第一项不是入口**：多半是剪贴板记录或同名文件排在了前面。用 `↓` 选中入口回车，用过几次后 Spotlight 就会把它排到第一。
- **图标没有更新**：这是系统图标缓存，稍等一会儿，或者执行 `killall Dock`。
