#!/bin/bash
# precompile_uvm.sh —— 两步法第 0 步之一：把 UVM 预编译进 UVM_LIB
#
# 必须在 precompile_apb.sh 之前执行：APB VIP 内部 import uvm_pkg::*，
# vlogan 分析 VIP 时要能从 UVM_LIB 里找到已分析好的 uvm_pkg。
#
# 库名 UVM_LIB 在 synopsys_sim.setup 里映射到 ./uvm_precompiled_lib，
# vlogan/vcs 都靠那个文件找库，所以三者必须一致。

set -e

UVM_LIB_DIR="./uvm_precompiled_lib"   # 必须与 synopsys_sim.setup 中 UVM_LIB 的映射一致

if [ -z "$VCS_HOME" ]; then
    echo "错误：VCS_HOME 未设置，请先 source project.cshrc"
    exit 1
fi

UVM_SRC="$VCS_HOME/etc/uvm-1.1"

echo "开始预编译 UVM 库到 UVM_LIB ($UVM_LIB_DIR) ..."

# 清掉旧库，避免残留的 AN.DB 与新版本混用导致诡异的解析失败
rm -rf "$UVM_LIB_DIR"
mkdir -p "$UVM_LIB_DIR"

# 不要加 -ntb_opts uvm-1.1：那个选项会让 VCS 自己再带一份 UVM 源码，
# 这里只要把 uvm_pkg.sv 干净地分析进 -work UVM_LIB 即可。
#
# 宏定义要与 cfg/sim.mk 的 USER_CMP_OPTS 一致，否则预编译出来的 uvm_pkg
# 与 TB 侧看到的不是同一份代码，elab 时会报类型不匹配。
#
# -kdb 必须加：后面 analyze/elab 都带 -kdb，若此处不加，
# 各库的 kdb 选项不一致，vcs 会报 Warning-[KDB-OPTIONS] 并削弱 Verdi 调试。
vlogan -full64 -sverilog +v2k \
       -work UVM_LIB \
       -kdb \
       +define+UVM_REG_DATA_WIDTH=32 \
       +define+UVM_PACKER_MAX_BYTES=1500000 \
       +define+UVM_DISABLE_AUTO_ITEM_RECORDING \
       +incdir+$UVM_SRC/src \
       $UVM_SRC/src/uvm_pkg.sv \
       -l precompile_uvm.log

echo "UVM 库预编译成功：$UVM_LIB_DIR"
echo "接下来执行： ./precompile_apb.sh"
