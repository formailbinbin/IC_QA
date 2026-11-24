#######################################################################################
#     dem_buck demo Makefile (VCS)
#
#     用法:
#       source /data2/project/Su2520/taohu/Su2520/script/project.cshrc
#       ./precompile_uvm.sh       # 第 0 步: 预编译 UVM 到 UVM_LIB (只需一次)
#       make comp                 # 编译 = analyze + elab (两步法)
#       make run TC=tc_buck_base  # 跑单个 case
#       make all TC=tc_buck_rate  # 编译+仿真
#       make regress              # 跑全部 case
#       make wave TC=tc_buck_base # 带 fsdb 波形
#       make verdi TC=tc_buck_base
#       make clean
#######################################################################################

DEM_BUCK_HOME := $(shell cd $(dir $(lastword $(MAKEFILE_LIST)))/.. && pwd)
export DEM_BUCK_HOME

TC        ?= tc_buck_base
SEED      ?= 1
VERB      ?= UVM_LOW
TIMEOUT_MS ?= 50

SIMV      := $(DEM_BUCK_HOME)/sim/simv
LOG_DIR   := $(DEM_BUCK_HOME)/sim/log
LOG       := $(LOG_DIR)/$(TC).log
UVM_SRC   =  $(VCS_HOME)/etc/uvm-1.1
# 全部 testcase
TC_LIST   := tc_buck_base tc_buck_rate tc_buck_burst tc_buck_pps tc_buck_shared tc_buck_beatgap

# ---------------- 两步法编译选项 ----------------
# 注意: analyze/elab 两步都【不能】加 -ntb_opts uvm-1.1，
#       否则 VCS 会把自带的 uvm_pkg 重新编译一份进 work 库，预编译就白做了。
#       UVM 只通过 -L UVM_LIB 引用预编译库，宏头文件靠 +incdir 找。

# 第 1 步 vlogan: 分析源码到 work 库。
#   注意: vlogan 不支持 -L（会被忽略并把库名当成源文件，报 SFCOR 错）。
#   vlogan 解析 import uvm_pkg::* 时，靠 synopsys_sim.setup 里的
#   UVM_LIB : ./uvm_precompiled_lib1 映射自动去该库找，无需任何选项。
VLOGAN_OPTS = -full64 -sverilog -timescale=1ns/1ps \
              +incdir+$(UVM_SRC)/src \
              -kdb \
              -l $(LOG_DIR)/analyze.log \
              -f $(DEM_BUCK_HOME)/cfg/tb.f

# 第 2 步 vcs: 只做精细化+链接，不再给源文件，用 -top 指定顶层。
#              -L UVM_LIB 在这里仍然需要，否则精细化时找不到 uvm_pkg。
#              uvm_dpi.cc 必须显式带上，否则链接时缺 UVM 的 DPI 符号。
VCS_OPTS  = -full64 -sverilog -timescale=1ns/1ps \
            -L UVM_LIB \
            $(UVM_SRC)/src/dpi/uvm_dpi.cc -CFLAGS -DVCS \
            -debug_access+all \
            -kdb \
            -l $(LOG_DIR)/elab.log \
            -o $(SIMV) \
            -top tb_top

SIM_OPTS  = +UVM_TESTNAME=$(TC) \
            +UVM_VERBOSITY=$(VERB) \
            +ntb_random_seed=$(SEED) \
            +TIMEOUT_MS=$(TIMEOUT_MS) \
            -l $(LOG)

.PHONY: all precompile analyze elab comp run wave verdi regress clean help

all: comp run

$(LOG_DIR):
	@mkdir -p $(LOG_DIR)

# 第 0 步：预编译 UVM（只需跑一次，UVM 很少变）
precompile:
	@echo "==== precompiling UVM into UVM_LIB ===="
	cd $(DEM_BUCK_HOME)/sim && ./precompile_uvm.sh

# 第 1 步：vlogan 分析 TB 源码，引用预编译的 UVM_LIB
analyze: $(LOG_DIR)
	@echo "==== [1/2] vlogan: analyzing dem_buck ===="
	@if [ ! -d $(DEM_BUCK_HOME)/sim/uvm_precompiled_lib1/AN.DB ]; then \
	    echo "错误: 未找到预编译的 UVM 库，请先执行 make precompile"; exit 1; \
	fi
	cd $(DEM_BUCK_HOME)/sim && vlogan $(VLOGAN_OPTS)

# 第 2 步：vcs 精细化+链接，不再传源文件
elab: $(LOG_DIR)
	@echo "==== [2/2] vcs: elaborating tb_top ===="
	cd $(DEM_BUCK_HOME)/sim && vcs $(VCS_OPTS)

comp: analyze elab

run: $(LOG_DIR)
	@echo "==== running $(TC) ===="
	cd $(DEM_BUCK_HOME)/sim && $(SIMV) $(SIM_OPTS)
	@echo "---- log: $(LOG) ----"

wave: $(LOG_DIR)
	cd $(DEM_BUCK_HOME)/sim && $(SIMV) $(SIM_OPTS) +FSDB

verdi:
	cd $(DEM_BUCK_HOME)/sim && verdi -dbdir $(SIMV).daidir -ssf tb_top.fsdb &

regress: comp
	@for tc in $(TC_LIST); do \
	    echo "==== regress: $$tc ===="; \
	    $(MAKE) run TC=$$tc SEED=$(SEED); \
	done
	@echo ""
	@echo "==== regress summary ===="
	@grep -H "TC_RESULT" -A 6 $(LOG_DIR)/tc_buck_*.log | grep -E "configured|measured|error" || true

clean:
	rm -rf $(DEM_BUCK_HOME)/sim/simv* $(DEM_BUCK_HOME)/sim/csrc \
	       $(DEM_BUCK_HOME)/sim/*.fsdb $(DEM_BUCK_HOME)/sim/*.vpd \
	       $(DEM_BUCK_HOME)/sim/ucli.key $(DEM_BUCK_HOME)/sim/vc_hdrs.h \
	       $(DEM_BUCK_HOME)/sim/novas* $(DEM_BUCK_HOME)/sim/verdiLog \
	       $(DEM_BUCK_HOME)/sim/work $(DEM_BUCK_HOME)/sim/AN.DB \
	       $(LOG_DIR)
	@echo "注意: 预编译库 uvm_precompiled_lib1 未删除，需重建请 make precompile"

help:
	@echo "make comp                 # compile"
	@echo "make run TC=<testcase>    # simulate"
	@echo "make all TC=<testcase>    # compile + simulate"
	@echo "make regress              # run all testcases"
	@echo "make wave TC=<testcase>   # simulate with fsdb"
	@echo "make clean"
	@echo ""
	@echo "available TC: $(TC_LIST)"
