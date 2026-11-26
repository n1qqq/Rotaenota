# Rotaenota

使用 Godot 4.4 / GDScript 探索 Rotaeno 核心游玩逻辑的原型：通过转动设备改变音符相对玩家的角度，再结合触摸完成判定。

**当前处于框架阶段，尚不能完整游玩。** 已有主菜单、选曲、设置、谱面文本解析和传感器实验代码；音乐播放、音符运动、判定和计分尚未实现。进入有效关卡还会遇到校准初始化错误。详细分析见 [陀螺仪检查报告](docs/gyroscope-review.md)。

## 运行

1. 使用 Godot **4.4.1 Standard** 导入根目录的 `project.godot`，等待资源导入。
2. 按 F6 可查看单独的界面；完整入口使用 F5，从主菜单点击进入选曲。
3. 项目已启用鼠标模拟触摸，桌面可以操作菜单。选择 `demo_0` 对应歌曲并点击 START 可进入关卡加载流程，但目前会在校准等待处报错。
4. 真实传感器输入需要导出至具备相应传感器的 Android / iOS 设备。Windows 上的普通运行不会提供手机的传感器读数；桌面调试需要注入模拟数据。[Godot Input 文档](https://docs.godotengine.org/en/4.4/classes/class_input.html)

项目使用 Mobile 渲染器，无 C# 或第三方插件依赖。`export_presets.cfg` 包含 Windows Desktop、Android 和 iOS 预设，导出路径尚为空，移动平台仍需安装对应导出模板并配置 SDK / 签名。打包时应将 `*.json, *.txt` 加入非资源文件导出过滤器，确保配置和谱面被包含；当前预设的 `include_filter` 为空。

不要直接运行 `level.tscn` 来测试正常启动：它依赖选曲界面写入的 `Globals.current_level_info`。

## 文件与流程

| 文件 | 当前职责 |
| --- | --- |
| `project.godot` | 主场景、Globals 自动加载、渲染器、鼠标模拟触摸及传感器开关 |
| `src/main_menu.gd` / `scn/main_menu.tscn` | 标题和点击进入选曲；脚本还保留了角度计算调试输出 |
| `src/level_select.gd` / `scn/level_select.tscn` | 扫描曲包、展示封面和信息、打开设置、启动关卡 |
| `src/level_list_item.gd` / `scn/level_list_item.tscn` | 曲包列表项和选择信号 |
| `src/settings.gd` / `scn/settings.tscn` | 输入模式、流速、时间偏移设置面板 |
| `src/globals.gd` | 共享设置、当前曲包及配置读取 |
| `src/chart_parser.gd` | 将自定义文本解析为 metadata / notes / lines 字典 |
| `src/level.gd` / `scn/level.tscn` | 校验曲包、加载背景和音频资源、整理谱面、启动传感器校准 |
| `src/gyroscope_initializer.gd` | 两秒加速度采样与重力方向估计 |
| `src/gyroscope_agent.gd` | 实验性的 Z 轴积分、姿态及角度修正 |
| `demo/demo_0/` | 有音频和谱面的最小示例，目前只有一个音符 |
| `demo/demo_1/` | 不完整的配置示例；缺少歌曲和谱面，`config.json2` 不会被读取 |
| `res/` | 面板、背景、默认封面与七张音符贴图 |
| `icon.svg` | Godot 默认图标资源 |
| `*.uid` / `*.import` | 脚本 UID 和资源导入设置 |
| `.godot/` | Godot 自动生成缓存，已由 `.gitignore` 排除 |

主流程是 `main_menu → level_select → level`，设置面板挂在选曲界面下，打开时暂停场景树。关卡的 `Notes` 目前只是空的 Node；两层面板和背景由 TextureRect 显示。还没有实际的三维场景、音符节点或判定圈逻辑。

## 曲包

曲包目录结构：

```text
Levels/
└── my_song/
    ├── config.json
    ├── crt.txt
    ├── song.mp3
    └── jacket.png
```

游戏优先扫描 `user://Levels/` 的直接子目录。**只有该目录不存在时**才扫描 `res://demo/`；空的 Levels 目录也会阻止示例曲包出现。可以在 Godot 编辑器中打开用户数据文件夹来定位 `user://`。

```json
{
  "title": "My Song",
  "author": "Chart Author",
  "difficulty": "5",
  "jacket": "jacket.png",
  "chart": "crt.txt",
  "song": "song.mp3",
  "preview": ""
}
```

路径相对于曲包目录。封面缺失时使用内置占位图；歌曲和谱面缺失会导致关卡加载失败。支持加载 MP3、Ogg Vorbis 和 WAV 音频资源，但尚未播放。`preview` 目前未使用；标题为空时从歌曲文件名推导。配置读取尚无完整的字段和类型校验，应保留上述字段。

## 谱面格式

语法是 `命令 | 子命令 : 参数 | 参数`。空行和空白可省略，支持 `//`、`#` 行注释和行尾注释。解析器先寻找 `//`，未找到才寻找 `#`，因此同一行不要混用两种注释标记。

```text
m | bpm : 105 | 0          // 从第 0 拍开始，BPM 为 105
n | s | b : 180 | 2        // 第 2 拍，180°，大 Slide
n | catch : 210 | 17.875   // 第 17.875 拍，210°，Catch
n | r | ccw : 2.5         // 第 2.5 拍，逆时针 Rotate
```

| 命令 | 参数与含义 |
| --- | --- |
| `m / meta` + `b / bpm` | `BPM值 | 起始拍` |
| `m / meta` + `l / line` | 线条元数据，行为未实现 |
| `n / note` + `t / tap` | `角度（度） | 拍数` |
| `n / note` + `s / slide / d / drag` | `角度 | 拍数`；小音符子类型 `s/small/l/little`，大音符 `b/big/L/Large` |
| `n / note` + `f / flick` | `角度 | 拍数` |
| `n / note` + `c / catch` | `角度 | 拍数` |
| `n / note` + `r / rotate` | `拍数`；顺时针子类型 `c/cw/clockwise/r/red`，逆时针 `cc/ccw/counterclockwise/b/blue` |

参数含义来自示例谱面约定，目前解析器仅拆分字段并将可解析的数值转为 int / float，不验证音符参数数量，也不将别名统一为同一种 type。Rotate 附加 `direction`，Slide 附加 `style`。`line` 元数据实际进入 `metadata`，返回的 `lines` 数组仍为空。

示例将 210° 标为左下方，对应数学角度约定：0° 向右，90° 向上。未来绘制到 Godot 二维画布时要处理屏幕 Y 轴向下的区别。拍数尚未转为秒；固定 BPM 下可用 `秒数 = 拍数 × 60 / BPM`，变速谱需要按 BPM 区段累加。当前 `initialize_chart_data()` 只复制并反转数组，没有时间计算或排序，不能依赖它修正乱序谱面。

## 空间与体感模型

目标是：音符在 timing `t` 到达角位置 `theta1`，玩家通过转动设备改变它在屏幕上的相对角位置；`phi` 不作为命中条件。径向距离由接近 timing 的过程决定，视觉上可以用二维极坐标表现，不必为每个音符创建三维物体。

Catch 在设备正左和正右各有判定点，因此设备旋转 180° 后可由另一侧接住同一角位置的音符。Rotate 按旋转角加速度判定，与起始设备角度无关。两者均不需要保存设备累计转过的圈数；角度 wrap 本身不是缺陷。

后续实现需要明确世界、设备、屏幕三套坐标，以及 theta 的零点和正方向。忽略 phi 的判定，并不意味着可以忽略设备倾斜对传感器坐标的影响。当前代码尚未把传感器输出接到绘制或判定上，详细的候选数学定义及限制见 [检查报告](docs/gyroscope-review.md#建议的角度定义)。

## 设置与当前缺口

三种模式的目标定义如下，默认使用 HANDHOLD：

| 模式 | 输入与角度含义 | 使用边界 |
| --- | --- | --- |
| HANDHOLD | 陀螺仪方向盘模式，表示手持设备的屏幕内倾斜角 | 不处理设备水平放置时的角度 |
| DESKTOP | 平放设备在桌面上的陀螺仪模式，以进入关卡并完成校准时的朝向为零点 | 不处理设备竖直放置（例如挂壁电视机）时的角度 |
| ACCEL | 加速度计模式，不关心设备在世界中的方位，只关心绕屏幕法线的偏转 | 依赖重力在屏幕平面的投影；水平放置时仅靠加速度计无法测出这种旋转 |

DESKTOP 指设备平放的使用方式。当前 HANDHOLD 与 DESKTOP 仍进入同一个空处理函数，ACCEL 的处理函数也为空，这些模式定义尚未完整实现。

默认流速为 4，界面范围 1–8；默认偏移为 0 ms，范围 ±2000 ms。`render_timing = 4` 表示预设的提前拍数，`render_pool = 128` 表示预设容量。这些值尚未驱动实际音符播放。

设置使用 `user://preferences.json`，但 `save_settings()` 只有在文件已存在时才写入，首次运行无法创建设置文件；读取也缺少损坏 JSON 和缺字段处理。

继续开发的主要顺序：

1. 修复校准实例和传感器节点生命周期，明确角度模型并加入模拟输入验证。
2. 建立音频播放时钟、BPM 时间映射、offset 的正负约定。
3. 实现音符池、接近动画、触摸角度转换及各类音符判定。
4. 补齐计分、结果、暂停/返回、配置校验和移动设备实测。

当前列表项会在触摸按下和松开时各触发一次选择；关卡返回函数没有连接到场景按钮；音符贴图虽已存在，还未被游戏脚本使用。
