编译添加
-fgp

仿真添加
			-fgp=num_threads:3 
			-fgp=num_fsdb_threads:1 
			-Xdprof=timeline 

-fgp=num_threads:3 表示并行仿真采用3核

-fgp=num_fsdb_threads:1 表示dump波形的时候单独分配一个核

-Xdprof=timeline 打开分析报告
会生成dprof.dir目录、dprof.txt clkthread.stats
      


根据行业实践，FGP 在特定类型的 RTL 或网表上效果更显著：

低功耗 RTL 设计：通常有 2-3 倍加速。

网络/多核 CPU 的 RTL 设计：通常有 3-4 倍加速。

图形处理器 RTL 设计：可达 5-7 倍加速。

门级网表（Gate-level）：可达 5-10 倍加速。

扫描/DFT 设计：加速比最高，可达 10-30 倍。
