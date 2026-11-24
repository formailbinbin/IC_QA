#!/bin/bash
# precompile_apb.sh —— 两步法第 0 步：把 Synopsys APB VIP 预编译进 APB_LIB
#
# 为什么值得预编译：
#   svt_apb.uvm.pkg 会连带展开 svt_uvm_pkg / svt_amba_common_uvm_pkg /
#   svt_apb_uvm_pkg 三个 package，是整个 VIP 里最耗时的部分。
#   一步流每次 make comp 都要重编一遍，预编译后只编一次。
#
# 两步法流程：
#   0) ./precompile_uvm.sh && ./precompile_apb.sh   # 只做一次
#   1) make analyze   # vlogan 分析 TB 源码，靠 synopsys_sim.setup 的库映射引用上面两个库
#   2) make elab      # vcs -top harness -L UVM_LIB -L APB_LIB 精细化出 simv
#
# 库名 APB_LIB 在 synopsys_sim.setup 里映射到 ./apb_precompiled_lib，
# vlogan/vcs 都靠那个文件找库，所以三者必须一致。

set -e

APB_LIB_DIR="./apb_precompiled_lib"   # 必须与 synopsys_sim.setup 中 APB_LIB 的映射一致

if [ -z "$VCS_HOME" ]; then
    echo "错误：VCS_HOME 未设置，请先 source project.cshrc"
    exit 1
fi
if [ -z "$DESIGNWARE_HOME" ]; then
    echo "错误：DESIGNWARE_HOME 未设置，请先 source project.cshrc"
    exit 1
fi

# VIP 版本。amba_svt 下有 latest 和 R-2020.12，这里锁定具体版本避免升级后行为突变。
AMBA_VER="R-2020.12"
AMBA_HOME="$DESIGNWARE_HOME/vip/svt/amba_svt/$AMBA_VER"
SVT_COMMON="$DESIGNWARE_HOME/vip/svt/common/$AMBA_VER"

if [ ! -d "$AMBA_HOME" ]; then
    echo "错误：找不到 APB VIP 目录 $AMBA_HOME"
    exit 1
fi

# APB VIP 内部 import uvm_pkg::*，必须先有预编译好的 UVM_LIB。
# vlogan 靠 synopsys_sim.setup 的库映射去 UVM_LIB 找已分析好的 uvm_pkg，
# 若 UVM_LIB 为空，VIP 里的 `SVT_XVM(report_object) 宏会展开失败，
# 报一堆莫名其妙的 Error-[SE] Syntax error。
if [ ! -d "./uvm_precompiled_lib/AN.DB" ]; then
    echo "错误：UVM_LIB 为空，请先执行 ./precompile_uvm.sh"
    exit 1
fi

echo "开始预编译 APB VIP 到 APB_LIB ($APB_LIB_DIR) ..."
echo "  AMBA_HOME = $AMBA_HOME"

# 清掉旧库，避免残留 AN.DB 与新版本混用导致诡异的解析失败
rm -rf "$APB_LIB_DIR"
mkdir -p "$APB_LIB_DIR"

# APB VIP 的 package 没有独立 .sv 文件，入口就是 svt_apb.uvm.pkg。
# 它内部用 `ifdef DESIGNWARE_INCDIR 决定走哪条 include 路径，必须显式定义。
#
# 不要加 -ntb_opts uvm-1.1：vlogan 下它不会把 uvm_pkg 分析进当前编译单元，
# uvm_pkg 必须来自上一步预编译好的 UVM_LIB（靠 synopsys_sim.setup 映射自动找到）。
#
# 编译宏要与 cfg/sim.mk 里的 USER_CMP_OPTS 完全一致，否则预编译出来的
# package 与 TB 侧看到的不是同一份代码，elab 时会报类型不匹配。
# 关键：svt_uvm_pkg.svi 里有 `include "uvm_pkg.sv"，若不拦住，uvm_pkg 会被
# 重复编一份进 APB_LIB，于是 elab 时出现两个互不兼容的类型：
#   class UVM_LIB.uvm_pkg::uvm_object  vs  class APB_LIB.uvm_pkg::uvm_object
# 用 uvm_pkg.sv 自己的 guard 宏 UVM_PKG_SV 把那次 include 变成空操作，
# 让 APB_LIB 去引用 UVM_LIB 里已有的那一份 uvm_pkg。
# 但 uvm_macros.svh 仍需显式提供，否则 VIP 里的 `uvm_*_utils 宏展开失败。
vlogan -full64 -sverilog +v2k \
       -work APB_LIB \
       -kdb \
       +define+UVM_PKG_SV \
       +define+DESIGNWARE_INCDIR=$DESIGNWARE_HOME \
       +define+SVT_UVM_TECHNOLOGY \
       +define+UVM_REG_DATA_WIDTH=32 \
       +define+UVM_PACKER_MAX_BYTES=1500000 \
       +define+UVM_DISABLE_AUTO_ITEM_RECORDING \
       +define+SVT_APB_PWDATA_WIDTH=32 \
       +incdir+$VCS_HOME/etc/uvm-1.1/src \
       +incdir+$SVT_COMMON/sverilog/include \
       +incdir+$AMBA_HOME/sverilog/include \
       $VCS_HOME/etc/uvm-1.1/src/uvm_macros.svh \
       $AMBA_HOME/sverilog/include/svt_apb.uvm.pkg \
       -l precompile_apb.log

echo "APB VIP 预编译成功：$APB_LIB_DIR"
echo "库中的 package："
grep -o 'svt_[a-z_]*_uvm_pkg' precompile_apb.log | sort -u
echo "接下来执行： make analyze && make elab"
