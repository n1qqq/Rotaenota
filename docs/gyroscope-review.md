# 体感输入模型与验证

校准与传感器节点生命周期已修复，三种模式现在输出角度、角速度、角加速度和有效状态。模拟输入测试覆盖数学模型与实际关卡启动、暂停、重试和退出；尚未进行手机实测。音符绘制、时间判定和计分仍未实现。

## 坐标与零点

设备坐标约定为 X 向屏幕右、Y 向屏幕上、Z 向屏幕外。角度使用弧度，逆时针为正；角速度为 rad/s，角加速度为 rad/s²。Godot 的二维屏幕 Y 轴向下，后续绘图应使用 `(cos(angle), -sin(angle))`。

| 模式 | 零点与角度 | 不支持的姿态 |
| --- | --- | --- |
| HANDHOLD | 屏幕上方朝上时的屏幕右侧为固定 0°；校准时斜着拿不会重设零点 | 水平放置及接近水平的区域 |
| DESKTOP | 以进入关卡完成校准时的屏幕右侧为 0°，测量相对于该朝向的桌面内转角 | 竖直放置及接近竖直的区域 |
| ACCEL | 同 HANDHOLD，只使用加速度计估计屏幕内偏转，不关心世界方位 | 水平放置时转角无法从重力观测 |

HANDHOLD / ACCEL 不需要知道设备朝向世界的哪个方位。DESKTOP 的重力只能确定桌面法线，桌面内的零点来自校准时建立的参考坐标，不来自磁北。

## 校准与节点生命周期

`level.gd` 先完成曲包加载，再创建 `GyroInitializer.new()` 实例；连接成功和失败信号后才加入场景树。初始化器不再访问父节点的隐式重力变量，也不再从 GDScript 资源读取实例属性。

校准要求连续两秒有效静止采样、至少 30 个样本。重力模长须在 `9.80665 ± 1.5 m/s²` 内；HANDHOLD / DESKTOP 的原始角速度模长须不大于 `0.08 rad/s`；重力方向相对于这段静止窗口起点的变化须不超过 2°。运动或无效数据会重启连续采样窗口，总等待超过八秒则失败。有效样本按时间加权估计重力方向和三轴角速度零偏；ACCEL 不依赖陀螺仪，零偏设为零。

收到成功信号后，关卡释放初始化器，以 `GyroAgent.new()` 创建已带脚本的节点，调用 `configure(mode, gravity_direction, gyro_bias_rad_s)`，再加入场景树。代理以物理帧读取输入，不再由关卡重复读取同一组传感器。

失败时不创建代理，显示失败原因并允许重试、返回。重试先释放旧节点。暂停或失焦立即释放传感器节点；恢复且未暂停时重新校准，避免使用未被跟踪的姿态。离开关卡由场景树释放子节点，没有跨场景存活的校准等待协程。

单次输入间隔超过 0.1 秒、有效重力丢失或实际姿态离开支持范围时，代理清除有效状态并要求重新校准。关卡在下一次物理更新启动新校准。DESKTOP 的零点也会随之重设；不尝试恢复缺失期间的转角。

静止时没有陀螺仪的设备与输出全零的陀螺仪无法仅靠这些读数区分。当前校准能检测缺少重力输入，不能保证检测所有“有加速度计、无陀螺仪”的设备；这种设备应选择 ACCEL，后续可补充平台能力查询。

## 角度模型

### HANDHOLD

令 `q` 为当前设备坐标到校准参考坐标的四元数，`g0` 为校准重力单位向量，`omega` 为扣除三轴静止零偏后的角速度：

```text
q = normalize(q * Quaternion(normalize(omega), length(omega) * dt))
g = inverse(q) * g0
alpha = atan2(-g.x, -g.y)
```

零角速度时跳过轴角构造。这里积分完整三轴角速度，不把 X/Y 旋转丢掉。重力观测通过四元数倾斜修正缓慢融合，时间常数为两秒；不会每隔几分钟硬重置方向。

定义 `h² = gx² + gy²`，对应的有符号角速度为：

```text
alpha_dot = omega_z - gz * (omega_x*gx + omega_y*gy) / h²
```

它来自 `dg/dt = -omega × g`，所以倾斜时通常不能直接拿 `gyro.z` 代替。对于同一 alpha、不同 phi 的方向族：

```text
g(alpha, phi) = (-sin(alpha)*cos(phi), -cos(alpha)*cos(phi), sin(phi))
```

在 `cos(phi)>0` 的有效范围内，投影角不随 phi 改变。绕世界重力轴转身也不改变该角。

当单位重力的屏幕投影长度小于 0.2 时，角度无效，相当于排除水平附近约 11.5° 的区域。这个阈值是当前实现参数，仍需按手机手感调节。

### DESKTOP

同样积分三轴四元数 `q`，校准时 `q=IDENTITY`。用校准重力确定水平面，并选择朝向初始屏幕正面的法线 `n`；将初始与当前屏幕右方向投影到该平面，得到 `r0` 和 `r`：

```text
r0 = project_to_plane(device_right, n)
r = project_to_plane(q * device_right, n)
alpha = atan2(dot(n, cross(r0, r)), dot(r0, r))
r_dot = project_to_plane(q * cross(omega, device_right), n)
alpha_dot = dot(n, cross(r, r_dot)) / dot(r, r)
```

设备一直平放时就是屏幕 Z 轴积分，零点为校准完成时的朝向。允许轻度离桌倾斜，通过投影避免将俯仰直接算作桌面转角；当单位重力 `abs(g.z)<0.2`，即接近竖直时，判为无效。

此模式仅扣除初始陀螺仪零偏，重力无法修正桌面内的长期航向漂移；需要用户重新校准或后续引入额外参考。没有伪造绝对航向。

### ACCEL

直接平滑加速度方向，时间常数 0.04 秒，再用 `atan2(-gx,-gy)` 得到角度。相邻角差先 wrap 到 ±π 再除以 dt，避免跨越角度边界时产生假的速度峰值。滤波权重使用 `1-exp(-dt/tau)`，且始终在同为单位向量的数据之间混合。

这种方法不依赖设备的世界方位，也不使用陀螺仪，但线性加速度会影响角度，水平放置时重力投影没有方向。无法用算法从不存在的重力方向信息恢复水平旋转。

## Catch 与 Rotate 的输入

代理输出：

| 字段 | 含义 |
| --- | --- |
| `output_angle_rad` | 当前模式下的设备角，wrap 到 `[-PI, PI)`，不保留圈数 |
| `angle_valid` | 当前角度是否可用于判定；无效时显示值可能仍是上一有效角 |
| `angular_velocity_rad_s` | 当前角度模型对应的有符号角速度 |
| `angular_acceleration_rad_s2` | 相邻角速度差分并低通后的有符号角加速度 |
| `acceleration_valid` | 是否已有足够连续历史样本可判断 Rotate |
| `is_calibrated` | 当前是否持有可继续使用的校准参考 |

Catch 在设备左右两侧各有判定点，因此角差按半圈等价。`MotionMath.catch_error(note_angle, device_angle)` 返回：

```text
abs(wrapf(note_angle - device_angle, -PI/2, PI/2))
```

设备转过 180° 后，另一侧可接住同一位置的音符。该函数仅计算角差，实际时间窗和容差尚未接入音符判定。

Rotate 使用角加速度，与起始角度和圈数无关。匀速转动的稳定输出为零；减速产生与角速度相反的角加速度。正加速度对应逆时针 Rotate，负加速度对应顺时针 Rotate。角加速度低通时间常数为 0.04 秒，突变后存在短暂滤波尾迹。首个角速度样本不产生加速度；ACCEL 需要先取得连续角度样本再取得连续速度样本。重校准或无效输入会清空差分历史，避免启动尖峰。判定阈值和时间窗仍待实现和实测。

## 平台输入

项目启用了 accelerometer、gyroscope 和 gravity 三个传感器开关。HANDHOLD / DESKTOP 优先使用 `Input.get_gravity()`，没有有效重力数据时回退到加速度计；ACCEL 始终使用加速度计。通过 `feed_sample(gyro, gravity, delta)` 注入模拟数据时，gravity 必须是 m/s²、已遵循设备坐标约定的向下重力样本。

Godot 4.4 的手机传感器 API 支持 Android / iOS，普通桌面可用 `Input.set_gyroscope()`、`set_gravity()` 和 `set_accelerometer()` 注入值。[Input 文档](https://docs.godotengine.org/en/4.4/classes/class_input.html)

Godot 4.4.1 Android 的输入处理已重映射显示方向，并在调用 `GodotLib.accelerometer` / `gravity` 前取反原生数据；陀螺仪不取反。iOS 将 Core Motion 的 gravity 与 userAcceleration 相加，按显示方向转换。因此游戏层不再次统一取反或补 180°。[Android 输入转换](https://github.com/godotengine/godot/blob/4.4.1-stable/platform/android/java/lib/src/org/godotengine/godot/input/InputEventRunnable.java#L321)、[iOS 输入转换](https://github.com/godotengine/godot/blob/4.4.1-stable/platform/ios/godot_view.mm#L375)

## 验证

运行 `godot --headless --path . --script tests/motion_test.gd`，使用 Godot 4.4.1。测试覆盖：

- 无传感器超时、连续静止要求、三轴零偏和错误持握姿态。
- HANDHOLD / ACCEL 在不同校准角、不同倾斜角下保留固定零点；DESKTOP 重校准后零点更新。
- HANDHOLD 改变倾斜或绕世界竖直轴转身时保持角度，DESKTOP 俯仰不产生转角。
- 30 / 60 / 120 FPS 下的角度与匀速输出，±π 边界不产生 Rotate 尖峰。
- 不同起始角下相同角加速度、减速产生反向角加速度，DESKTOP / ACCEL 的负向角加速度。
- Catch 的左右半圈等价、异常采样间隔、静止零偏扣除和传感器读数来源。
- 真实 `level.tscn` 的校准成功、失败重试、暂停恢复、失焦与暂停交叠、节点释放和离开关卡。

模拟验证不包含真实手机噪声、传感器采样延迟、丢采样或长期漂移。当前手机验收重点是：固定横屏运行，检查顺逆转动的符号；以不同倾斜角完成同一目标动作；匀速、加速、减速分别记录输出；验证无效姿态恢复和 DESKTOP 重校准零点；静置数分钟检查漂移。滤波、稳定性和有效范围阈值应根据这些数据调节。

## 已修复的旧问题

移除了脚本资源与实例混用、先加入空 Node 再挂脚本、校准前启动积分、`180*PI` 单位错误、仅用 Z 的伪完整姿态、无数据仍宣布校准完成、单位向量与原始加速度混合滤波，以及永不执行的定时重校准分支。原先关于必须保留累计圈数的判断也已撤回：游戏无需圈数，wrap 本身是正确行为。
