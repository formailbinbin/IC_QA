#!/bin/bash
# precompile_uvm.sh —— 两步法第 0 步：把 UVM 预编译进 UVM_LIB
#
# 两步法流程：
#   0) ./precompile_uvm.sh      # 只做一次，UVM 很少变
#   1) make analyze             # vlogan 分析 TB 源码，-L UVM_LIB 引用预编译库
#   2) make elab                # vcs -top tb_top 精细化出 simv
#
# 库名 UVM_LIB 在 synopsys_sim.setup 里映射到实际目录，
# vlogan/vcs 都靠那个文件找库，所以三者必须一致。

set -e

UVM_SRC="$VCS_HOME/etc/uvm-1.1"
UVM_LIB_DIR="./uvm_precompiled_lib1"   # 必须与 synopsys_sim.setup 中 UVM_LIB 的映射一致

if [ -z "$VCS_HOME" ]; then
    echo "错误：VCS_HOME 未设置，请先 source project.cshrc"
    exit 1
fi

echo "开始预编译 UVM 库到 UVM_LIB ($UVM_LIB_DIR) ..."

# 清掉旧库，避免残留的 AN.DB 与新版本混用导致诡异的解析失败
rm -rf "$UVM_LIB_DIR"
mkdir -p "$UVM_LIB_DIR"

# 不要加 -ntb_opts uvm-1.1：那个选项会让 VCS 自己再带一份 UVM 源码，
# 这里只要把 uvm_pkg.sv 干净地分析进 -work UVM_LIB 即可。
#
# -kdb 必须加：后面 analyze/elab 两步都带 -kdb，若此处不加，
# 各库的 kdb 选项不一致，vcs 会报 Warning-[KDB-OPTIONS]。
vlogan -full64 -sverilog \
       -work UVM_LIB \
       +incdir+$UVM_SRC/src \
       -kdb \
       $UVM_SRC/src/uvm_pkg.sv \
       -l precompile_uvm.log

echo "UVM 库预编译成功：$UVM_LIB_DIR"
echo "接下来执行： make analyze && make elab"
