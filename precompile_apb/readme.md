cd /data2/project/Su2521/taohu/Su2521
source ./script/project.cshrc        # 必须在工程根目录 source
cd verification/block/vbd_pre/sim
make run tc=tc_reg_hw_reset



./precompile_uvm.sh      # 必须先跑这个
./precompile_apb.sh      # APB 依赖 UVM_LIB，顺序不能颠倒


其他常用
make analyze                  # 只想单独验证第一步语法
make cmp                      # 会自动先 analyze
make ncrun tc=xxx             # 已编译好，只换 tc 重跑，不重新编译
make verdi_c                  # 看波形（两步法下不要用 make verdi）
make run twostep=off tc=xxx   # 退回原来的一步流对比
