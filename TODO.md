### 还要做

#### cache

- 设置cache（大小行列）
- 映射方式（组相联）
- 替换策略（如LRU）
- 命中率分析（要做访存测试程序）
   可以写几个访存测试程序用于命中率分析：

```
顺序访问数组
重复访问少量地址
跨步访问
循环累加
随机地址访问
```

统计：

```
hit_count
miss_count
access_count
hit_rate = hit_count / access_count
miss_rate = miss_count / access_count
AMAT = hit_time + miss_rate * miss_penalty
```

#### 拓展乘除法、浮点运算指令

浮点运算难度高于乘除法，需要实现

```
浮点寄存器堆
浮点加减乘除单元
舍入模式
NaN / Inf / 非规格数处理
浮点 load/store
```

#### 基于RISC-V设计自己的指令

写点小工具函数 ，如max(a,b)

#### 功耗性能面积分析

vivado能够给出所需要的参数

#### 系统性能瓶颈分析及优化方案

```
分支导致 flush
load-use 导致 stall
访存没有 Cache
当前 imem/dmem 可能没有映射 BRAM
组合逻辑路径较长，WNS 可能为负
I/O 和数据存储共享访存路径
```

解决方案

```
加入分支预测或提前分支判断
优化 forwarding，减少 stall
加入 Cache 或 BRAM 存储
把长组合路径拆分流水级
对乘除法采用多周期单元
用性能计数器统计 stall/flush 占比
```