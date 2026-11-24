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
      
