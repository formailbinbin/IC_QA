
export assert = on
export assert_dbg = off
export fcov = off
export ccov = off
export udl = ../cfg/tb.f
export pl ?= UVM_HIGH
export uco =
export uro =
export wave = on
export ralf = ral_CSR_VBD
export tc = vbd_sanity_test
export fuzzy=off
export adc_csr_mode=off
export cell = on
export fusa_mode=off
export async_rand=off
export initreg = x
export xprop = off

# ===== 两步法编译（vlogan analyze -> vcs elab），复用预编译库 =====
# UVM_LIB / APB_LIB 由 sim/precompile_uvm.sh、sim/precompile_apb.sh 生成，
# 库名到目录的映射在 sim/synopsys_sim.setup 里，三者必须一致。
# postsim netlist 流的源文件是在 prj_sim.mk 里追加到 USER_CMP_OPTS 的，
# 那套走不了两步法，所以 postsim=on 时自动退回一步流。
twostep ?= on
ifeq ($(postsim),on)
    twostep := off
endif

AMBA_VER   = R-2020.12
AMBA_HOME  = $(DESIGNWARE_HOME)/vip/svt/amba_svt/$(AMBA_VER)
SVT_COMMON = $(DESIGNWARE_HOME)/vip/svt/common/$(AMBA_VER)
UVM_SRC    = $(VCS_HOME)/etc/uvm-1.1/src

# analyze 与 elab 必须看到完全一致的宏，否则 package 里的类型对不上
CMP_DEFINES = +define+SVT_UVM_TECHNOLOGY \
              +define+UVM_REG_DATA_WIDTH=32 \
              +define+UVM_PACKER_MAX_BYTES=1500000 \
              +define+UVM_DISABLE_AUTO_ITEM_RECORDING \
              +define+SVT_APB_PWDATA_WIDTH=32 \
              +define+FOR_BT

ifeq ($(twostep),on)
# APB VIP 的 package / interface 已经在 APB_LIB 里了，TB 侧不能再本地展开一遍，
# 否则同一个 package 会存在两份互不兼容的类型，elab 直接报
#   class APB_LIB.uvm_pkg::uvm_object  vs  class UVM_LIB.uvm_pkg::uvm_object
# 这两个 guard 宏就是 VIP 文件自己的头部 `ifndef，定义掉即可让 include 变空操作：
#   GUARD_SVT_APB_UVM_PKG -> env/vbd_env_def.sv 的 `include "svt_apb.uvm.pkg"
#   GUARD_SVT_APB_IF_SVI  -> env/vbd_env_def.sv 的 `include "svt_apb_if.svi"
PRECOMP_GUARDS = +define+GUARD_SVT_APB_UVM_PKG +define+GUARD_SVT_APB_IF_SVI

# 第一步：读所有 HDL 源码。选项都是"读文件时才起作用"的那一类。
# 不能加 -ntb_opts uvm-1.1：vlogan 下它不会把 uvm_pkg 放进当前编译单元，
# uvm_pkg 要从 UVM_LIB 里来（靠 synopsys_sim.setup 自动找）。
# 但它顺带注入的 uvm_macros.svh 没了，所以必须显式放在 filelist 之前。
export VLOGAN_OPTS = $(uco) -full64 -sverilog +v2k -kdb -timescale=1ns/1ps \
                     +error+99 \
                     +lint=PCWM \
                     +lint=TFIPC-L \
                     $(PRECOMP_GUARDS) \
                     +define+DESIGNWARE_INCDIR=$(DESIGNWARE_HOME) \
                     $(CMP_DEFINES) \
                     +incdir+$(UVM_SRC) \
                     +incdir+$(SVT_COMMON)/sverilog/include \
                     +incdir+$(AMBA_HOME)/sverilog/include \
                     $(SRC_OPTS) \
                     $(UVM_SRC)/uvm_macros.svh \
                     -f $(udl)

# 第二步：精细化。只留"连网表/链接时才起作用"的选项。
# -L 对 module/interface 的库搜索生效（harness 里的 svt_apb_if 就靠它）；
# package 不走 -L，是 vlogan 阶段按库映射解析好的。
# uvm_dpi.cc 原来由 -ntb_opts 自动链接，现在要手动给。
# -top harness 由 prj_sim.mk 统一追加，这里不重复。
export USER_CMP_OPTS = -full64 +plusarg_save +vcs+lic+wait -timescale=1ns/1ps \
                       +nospecify +notimingcheck \
                       -L APB_LIB -L UVM_LIB \
                       $(UVM_SRC)/dpi/uvm_dpi.cc -CFLAGS -DVCS
else
export USER_CMP_OPTS = $(uco) -sverilog +v2k -full64 +plusarg_save +vcs+lic+wait\
                       +error+99\
                       +nospecify +notimingcheck -timescale=1ns/1ps \
                       -ntb_opts uvm-1.1\
                       +lint=PCWM \
                       +lint=TFIPC-L \
                       -top harness -f $(udl) \
                       $(CMP_DEFINES)
endif

export USER_RUN_OPTS = $(uro) +vcs+lic+wait +fsdb+force -assert nopostproc\
                       +UVM_MAX_QUIT_COUNT=99,0\
                       +uvm_set_severity=*,RNDFLD,UVM_WARNING,UVM_FATAL\
                       +UVM_TESTNAME=$(tc)\
                       +UVM_VERBOSITY=$(pl)\
                       +ntb_random_seed=$(SEED)\
                       +tc=$(tc) +seed=$(SEED)
ifeq ($(cell),on)
	USER_CMP_OPTS += -debug_region=cell+lib
	USER_RUN_OPTS += +fsdb+skip_cell_instance=0 
endif
ifeq ($(async_rand),on)
	SRC_OPTS += -F ../../../common/async_rand/async_rand.f \
					 +define+SYNC_RANDOM_SIM	
endif
ifeq ($(assert),on)
    SRC_OPTS += +define+ASSERT_ON
endif

ifeq ($(fcov),on)
    SRC_OPTS += +define+FCOV_ON
endif

ifeq ($(ccov),on)
    CM_OPTS = -cm line+cond+fsm+tgl+assert\
	             -cm_line contassign\
	             -cm_cond ports+tf+for+event+allops\
	             -cm_tgl portsonly\
	             -cm_glitch 0
    # 覆盖率插桩在 analyze 时打进 AN.DB，elab 时还要再给一次才会收集
    SRC_OPTS += $(CM_OPTS)
ifeq ($(twostep),on)
    USER_CMP_OPTS += $(CM_OPTS)
endif
    USER_RUN_OPTS += -cm line+cond+fsm+tgl+assert
endif
ifeq ($(xprop),on)
    USER_CMP_OPTS += -xprop=../cfg/xprop_cfg/xprop_cfg
endif

ifneq ($(initreg),)
ifeq ($(initreg), 0)
	USER_RUN_OPTS += +vcs+initreg+config+../cfg/initreg_cfg/initreg_0_cfg
else ifeq ($(initreg), 1) 
	USER_RUN_OPTS += +vcs+initreg+config+../cfg/initreg_cfg/initreg_1_cfg
else ifeq ($(initreg), x)
	USER_RUN_OPTS += +vcs+initreg+config+../cfg/initreg_cfg/initreg_x_cfg
else ifeq ($(initreg), z) 
	USER_RUN_OPTS += +vcs+initreg+config+../cfg/initreg_cfg/initreg_z_cfg
else ifeq ($(initreg), random) 
	USER_RUN_OPTS += +vcs+initreg+config+../cfg/initreg_cfg/initreg_random_cfg
else
	USER_RUN_OPTS += +vcs+initreg+config+../cfg/initreg_cfg/initreg_random_seed_cfg
endif
endif

ifeq ($(fuzzy),on)
    SRC_OPTS += +define+FUZZY_MODE
endif
ifeq ($(findstring fusa_mode,$(mode)),fusa_mode)
	fusa_mode := on
endif
ifeq ($(fusa_mode),on)
    SRC_OPTS += +define+FUSA_MODE
endif
ifeq ($(findstring adc_csr_mode,$(mode)),adc_csr_mode)
	adc_csr_mode := on
endif
ifeq ($(adc_csr_mode),on)
    SRC_OPTS += +define+ADC_CSR_MODE
endif
ifeq ($(assert_dbg),on)
    USER_RUN_OPTS += +fsdb+sva_success
endif

# 一步流时，上面这些"读文件时起作用"的选项还是得回到 vcs 命令行上
ifneq ($(twostep),on)
    USER_CMP_OPTS += $(SRC_OPTS)
endif

include ../../../../script/prj_sim.mk

# prj_sim.mk 是全工程共享的，不能改，这里只追加两步法需要的 analyze 目标，
# 并让它排在 cmp 之前。vlogan 产出 ./work（AN.DB），vcs 再从库里取。
# 注意：两步法下 prj_sim.mk 的 `make verdi` 用不了（它把 USER_CMP_OPTS 当一步流用），
# 看波形请用 `make verdi_c`（-simBin 读 simv 的 KDB，信息更全）。
ifeq ($(twostep),on)
cmp: analyze

analyze:
	@make make_dir
	@rm -rf ./work
	@vlogan $(VLOGAN_OPTS) -l $(LOG_DIR)/analyze.log

.PHONY: analyze
endif
gen_ral:
	ralgen -full64 -t CSR_VBD -B -o ../ral/$(ralf) -I sv -uvm ../../../../script/csr_gen/ralf_release/csr_vbd.ralf

mcov:
	# urg -full64  -dir $(mode)/cov/scope/simv.vdb -dbname $(mode)/cov/scope/merge1/merged -format both
	# urg -full64 -show ratios -show tests -parallel -dir $(mode)/cov/scope/simv.vdb -dbname $(mode)/co
	urg -full64 -parallel -dir $(mode)/cov/scope/simv.vdb -dbname $(mode)/cov/scope/merge.vdb -noreport

plan:
	hvp annotate -lca -plan ../doc/testpoint.xml -dir $(mode)/cov/scope/merge.vdb/

all:mcov plan
.DEFAULT_GOAL := run


