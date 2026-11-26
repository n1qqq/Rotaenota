# 陀螺仪逻辑检查

检查基于当前源码、Godot 4.4.1 的无窗口运行和合成角速度输入。结论：**现有逻辑不能正确覆盖任意持握姿态，且校准到关卡的连接已经存在可复现错误。** 本次交付为 README 和检查报告，游戏源码未修改。尚未进行手机实测，不能据此评价实际延迟、噪声和手感。

## 已确认的问题

| 优先级 | 位置 | 问题与后果 |
| --- | --- | --- |
| 阻断 | `src/level.gd:40,47` | `gyro_initializer` 是 preload 得到的 GDScript 资源，运行中的实例是 `gyro_init`。访问资源的 `is_calibrating` 会直接报错；后续 `gravity_vector` 读取也用错对象。 |
| 阻断 | `src/level.gd:22,38` | 先将普通 Node 加入树，再 `set_script`，不会因此重新调用新脚本的 `_ready()`。实测代理的校准时间仍为 0。应该实例化带脚本的代理，再加入树。 |
| 高 | `src/level.gd:36–48` | 代理在校准完成之前就启动，即使修复上面两处，它也会过早读取父节点的默认重力。应先完成有效校准，再向代理传入结果并启动积分。 |
| 高 | `src/gyroscope_agent.gd:41,88,92` | `screen_orientation` 声明为 0/1，赋值却为 0/180，最后再乘 π。180π 等于 32400°，即 90 圈；取模后是 0°，根本没有补偿半圈。 |
| 高 | `src/gyroscope_agent.gd:58–67` | 四元数和标量都只积分 `gyro.z`，完全丢弃 X、Y 分量。四元数因此不是完整设备姿态；后面的 `device_y_world` 无法描述真实倾斜。 |
| 高 | `src/gyroscope_agent.gd:23,52–53` | 将重力投影角当作初始角，却用局部 Z 角速度累加；二者不是任意姿态下同一个角度的值与导数。 |
| 高 | `src/gyroscope_initializer.gd:38–41` | “加速度永远与重力方向相反”的假设不成立于所有 Godot 平台实现。直接取反需要按引擎实际坐标验证，不能沿用原生传感器的直觉。 |
| 中 | `src/gyroscope_initializer.gd:15–55` | 只有两秒超时，没有有效样本计数和稳定性检测。无传感器时保留非零默认向量，仍报告校准完成。只要求模长 ≥8 也会接受强烈运动。 |
| 中 | `src/gyroscope_initializer.gd:41` | 上一帧归一化为长度 1，再与约 9.8 的原始向量 lerp，实际权重不是声明的 0.1；60 FPS 下方向贡献比例约为 0.98/(0.9+0.98)≈52%，不能按 10% 低通理解。 |
| 中 | `src/gyroscope_agent.gd:15,23,107` | `gyro_bias_z` 存放的是角度偏置，未测量/扣除陀螺仪零速偏置（rad/s）。自动重校准被 `if false` 永久禁用，漂移阈值常量未使用。 |
| 阻断游玩 | `src/level.gd:84–127` | 体感和触摸处理为 pass；没有读取 `corrected_2d_rotation` 的游戏逻辑。音乐只加载未播放，也没有音符运动或判定。 |

`_apply_orientation_logic()` 还有两个概念问题：点积大于零表示 Y 轴与重力同向，注释却写为“朝上”；它也不是操作系统的显示方向检测。对于固定屏幕坐标中的完整 360° 转角，`atan2` 本身已包含半平面信息，无需额外靠猜测加 π。应先明确该分支想解决的是显示方向改变、姿态翻转还是角度展开。

## 建议的角度定义

用户提出的 `(rho, theta, phi)` 尚未指定极轴。以下采用与体感方向盘接近的解释：**theta 是设备相对重力的屏幕内倾斜角；改变持握倾斜程度或绕世界竖直方向转身，不额外改变目标角。** 如果 theta 实际指世界水平面内的方位角，则重力本身无法观测这个角，需要另一套航向参考或相对姿态定义。

定义设备坐标为 X 向屏幕右、Y 向屏幕上、Z 向屏幕外。令 `g=(gx,gy,gz)` 为该坐标系内的向下重力，先从传感器输出转换到这个约定；Godot 的 Vector3.DOWN 是 `(0,-1,0)`，二维 Vector2.DOWN 则是 `(0,1)`。

当重力在屏幕平面的投影非零时，可定义投影角：

```text
h = sqrt(gx² + gy²)
theta_g = atan2(gx, -gy)
```

这个角描述重力投影，设备旋转角的符号需要根据游戏约定取反并减去初始参考。对同一 theta 的一族方向：

```text
g(theta, phi) = (sin(theta) cos(phi), -cos(theta) cos(phi), sin(phi))
```

只要 `cos(phi)>0`，代入就得到相同的 `theta_g`，phi 不参与判定。绕世界重力轴转身也不会改变设备内的重力向量。这给出了可以直接测试的“phi 无关”含义。

但当屏幕水平、`h≈0` 时，重力投影没有方向，`atan2(0,0)` 即使返回数值也没有物理意义。跨过这个极点后投影还可能反向。不能承诺“仅加速度计，在所有持握角度都可稳定识别完整 360°”。应规定可用姿态范围，或在此区域用完整陀螺仪姿态短时延续角度并控制恢复时的校正，避免突然翻转。

### 为什么只积分 Z 不够

在上述设备坐标内，固定世界重力满足：

```text
dg/dt = -omega × g
d(theta_g)/dt = -omega_z + gz * (omega_x*gx + omega_y*gy) / (gx²+gy²)
```

这是从投影角定义直接求导的结果。只有在 `gz=0` 或额外项恰好为零等特殊情况下，投影角速度才简化为 `-omega_z`。这正是“phi 不参与判定”仍然需要处理三轴姿态的原因。

实现时更适合在完整四元数中处理姿态，再提取目标角，避免直接在接近奇点的公式上积分。若 `q` 表示设备坐标到参考坐标的旋转，陀螺仪 `omega` 使用设备坐标，可采用：

```text
w = omega - measured_gyro_bias
q = normalize(q * Quaternion(normalize(w), length(w) * dt))
g_device = inverse(q) * g_reference
```

`w≈0` 时跳过轴角构造；初始 `q` 与 `g_reference` 必须使用同一校准约定。重力可用来缓慢校正可观测的倾斜漂移，不能修正绕重力轴的绝对航向漂移。运动加速度大或投影太小时应降低/停止对应校正；不要固定三分钟后硬重置到单位四元数。

游戏不需要累计圈数。`total_z_rotation` 目前实际上是积分得到并 wrap 到 ±π 的角度；wrap 本身没有问题，转满一圈返回原角度也是正确行为。如果需要计算相邻帧角度差，应使用 `delta_angle = wrapf(angle - previous_angle, -PI, PI)`，避免跨边界直接相减产生假跳变，无需再累加成总转角。这个差分要求相邻采样实际转角小于 π。

### Catch 与 Rotate 的判定规则

按项目作者补充的规则，设备正右、正左各有一个 Catch 判定点。设设备正右的世界角为 `alpha`，则两个判定点为 `alpha` 与 `alpha+PI`。对音符角 `theta_note`，角度误差可以写为：

```text
catch_error = abs(wrapf(theta_note - alpha, -PI/2, PI/2))
```

误差在容许范围内且满足时间条件即可接住。因此对于 Catch，设备角按 π 等价：0° 的音符在设备转过 180° 后可由左侧判定点接住。这里假设两侧使用相同的判定容差；这条等价关系不应直接推广为所有音符和画面都只需要半圈角度。

Rotate 按作者指定使用有符号的旋转角加速度判定，与起始设备角度和累计圈数无关。持续匀速旋转不触发 Rotate；减速产生与转动方向相反的角加速度，按该加速度方向判定。应先得到游戏所需旋转自由度的有符号角速度，再对时间求导得到角加速度；不能把角速度读数直接当成角加速度。差分需要滤波，并在初始化、暂停恢复或采样间隔异常时重置历史值，避免虚假的加速度峰值。阈值和时间窗仍需在实际判定实现中明确。

### 音符与触摸应共用一个角度空间

建议统一数学约定：世界音符角 `theta_note`，设备逆时针转角 `alpha`，屏幕内数学角 `beta = theta_note - alpha`。屏幕位置为：

```text
x = center_x + radius * cos(beta)
y = center_y - radius * sin(beta)
```

触摸点先转回数学角 `beta_touch = atan2(-(y-center_y), x-center_x)`，再用 `theta_touch = beta_touch + alpha` 与谱面角比较，误差取最短圆周差。绘制与判定必须使用同一帧的 alpha；谱面角由度转弧度一次即可。径向时间函数只需要在音符 timing 满足 `radius(timing)=判定圈半径`，phi 不加入命中条件。

以上是后续实现约定，当前项目尚无这些绘制与判定代码，也没有足够信息声称这与 Rotaeno 内部实现完全相同。

## Godot 传感器约定

Godot 4.4 的 `get_gyroscope()` 返回设备各轴的角速度，单位 rad/s；加速度为 m/s²。手机传感器读取支持 Android / iOS，桌面可以用 `Input.set_gyroscope()`、`set_accelerometer()` 等注入测试值。Android 使用 `get_gravity()` 还需启用 `input_devices/sensors/enable_gravity`，当前项目未显式启用该项。[Input 文档](https://docs.godotengine.org/en/4.4/classes/class_input.html)

Godot 4.4.1 的 iOS 实现将 Core Motion 的 gravity 与 userAcceleration 相加作为 accelerometer，并按界面方向转换坐标；静止时该值与传入引擎的 gravity 同向。因此项目无条件 `-accel` 至少不符合这个平台的实现。[iOS 源码](https://github.com/godotengine/godot/blob/4.4.1-stable/platform/ios/godot_view.mm#L375)

Android 的输入层同样会按照显示方向重映射传感器 X/Y 分量。后续适配要检查完整的平台转换链，在固定横屏下用已知姿态验证轴向，避免重复做 90° / 180° 转换。[Android 源码](https://github.com/godotengine/godot/blob/4.4.1-stable/platform/android/java/lib/src/org/godotengine/godot/input/GodotInputHandler.java#L687)

## 验证结果与后续验收

本机使用 Godot `4.4.1.stable.official.49a5bc7b6`。无窗口编辑器扫描没有报告 GDScript 解析错误，但输出了系统证书读取和编辑器设置写入权限错误，不能称为完全干净的检查。随后在 SceneTree 测试脚本中加载真实 demo_0 配置、实例化关卡，并直接调用传感器代理的数学函数，得到：

| 输入或操作 | 实际结果 |
| --- | --- |
| `_update_rotation_state(Vector3(PI/2,0,0), 1.0)` | 四元数仍为 `(0,0,0,1)`，X 轴 90° 完全丢失 |
| 默认状态执行 `_apply_orientation_logic()` | `screen_orientation=180`，乘 π 后为 32400° |
| Z 轴输入 TAU rad/s，持续 1 秒 | wrap 后角度约 `1.75e-7` rad，即数值误差范围内的 0；符合不保留圈数的需求，不属于缺陷 |
| 使用有效 demo_0 启动关卡 | `level.gd:40` 报 `Invalid access ... is_calibrating ... GDScript` |
| 等待 2.5 秒后读取代理状态 | `last_calibration_time=0`，后挂脚本没有执行预期 `_ready()` |
| 桌面零加速度输入 | 初始化器仍报告重力校准完成，返回默认 `(0,-1,0)` |

修复后应先用合成姿态生成 `g_device=q.inverse()*g_reference` 及对应角速度，测试恒定角、顺逆转动、±π 边界、相同 theta 不同 phi、纯世界竖直轴转动、水平极点、无传感器和不同帧率。Catch 应验证设备角相差 180° 时两侧判定等价；Rotate 应验证相同旋转角加速度在不同初始角下结果一致，并测试匀速、加速、减速和暂停恢复。合成输入可以确定数学与生命周期是否正确，不能替代真实传感器测试。

手机验收时固定屏幕方向：静止持握完成校准；分别转动 ±90°、180°、360°；维持相同目标角改变倾斜程度；绕世界竖直轴转身；短时水平持握；最后静置数分钟观察漂移。应记录原始 gyro/accel、估计重力、角度和有效状态，并显示简单方向指示器，才能区分传感器误差、姿态映射错误和渲染符号错误。
