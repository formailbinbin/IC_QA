# ============================================================
# run_fpv.tcl : RR 仲裁器 FPV 签核脚本
# 用法: vcf -f run_fpv.tcl              (批处理)
#       vcf -verdi -f run_fpv.tcl       (带 GUI 看反例波形)
# ============================================================

# ---------- 0. App 选择 ----------
# FPV : 性质验证（assert/cover）     CC  : 连线等价
# AEP : 自动抽取性质                 COV : 形式覆盖率/不可达分析
# DPV : 数据通路等价                 SEQ : 顺序等价
set_fml_appmode FPV

# ---------- 1. 读设计 + 属性文件 ----------
# -sva 打开断言解析；+define+FORMAL 让 RTL 里的形式专用代码生效
#（例如把大 FIFO 缩参、把不可综合的统计逻辑关掉）
# -cov line+branch+tgl : 编译期做覆盖率插装。
#   注意 -cov 是 read_file 的选项，不是 check_fv 的（原脚本把它写到
#   check_fv 上，才会报 unknown option '-cov' CMD-010）。
#   不在这里插装，后面 compute_cov 就没有任何 coverage goal，
#   会报 AUTO_SCALE_NO_PROPERTIES。
read_file -top arb_rr -format sverilog -sva    \
          -cov line+branch+tgl                 \
          -vcs {-sverilog +define+FORMAL       \
                ../design/arb_rr.sv               \
                ../design/arb_fpv.sv}

# ---------- 2. 时钟 ----------
create_clock clk -period 10

# ---------- 3. 复位 ----------
# -sense low 表示低有效；多复位就多写几条 create_reset
create_reset rst_n -sense low

# 跑复位序列直到状态稳定，然后把复位后状态存为初始状态
# 这一步最容易出错：如果 -stable 没收敛，所有证明都是从 X 态开始的垃圾结果
sim_run -stable
sim_save_reset

# ---------- 4. 约束（宁少勿多，见 19.7.6） ----------
# 4.1 指针推进约定（ap_bound 成立的必要前提）
#     upd 是顶层输入，不加约束时形式工具会让它永远为 0：
#     mask 永不更新 -> RR 退化成固定优先级 -> 高编号请求永久饿死，
#     ap_bound 必然在 depth=N 附近被证伪（这正是之前那条反例）。
#     RR 的硬件约定是「授权被接受时推进指针」，即 upd 跟随 gnt_vld。
#     若实际系统里 upd 来自下游 ready（可能背压若干拍），把下面这条换成
#     「upd 不能连续拉低超过 K 拍」的弱约束，并把 BOUND 放大到 (N-1)*(K+1)。
#     本版本语法是 fvassume -expr {表达式} <名字>，没有 -add / -name。
fvassume -expr {upd == gnt_vld} am_upd_on_grant

# 配置寄存器类信号可以安全冻结
#fvassume -expr {$stable(cfg_mode)}      am_cfg_stable
# 权重范围约束：把 liveness 的 BOUND 压小，必须有硬件依据
#fvassume -expr {weight_q inside {[1:3]}} am_weight_range

# ---------- 5. 证明 ----------
# 先设一个合理的 effort / 时间上限，避免单条性质吃掉整晚
#set_fml_var fml_max_time 3600
check_fv -block

# ---------- 6. 结果 ----------
report_fv -list    > fpv_result.rpt
report_fv -verbose > fpv_verbose.rpt

# ---------- 7. 收尾 ----------
# 7.1 vacuity：assume 是否过强导致 assert 空洞通过
#     本版本 check_fv -block 已经自动把 vacuity 子目标一起跑了
#     （见 report_fv 里的 Vacuity 段），不需要也不能再单独 check 一次，
#     否则会因为 "已收敛" 而报 NO_PROPERTIES_FOUND。直接出报告即可。
#     正确写法是用 -vacuity 过滤（本版本 report_fv 没有 -subtype，
#     -type 也不接受 vacuity）。先出全量 vacuity 视图，再单独列出可疑项。
report_fv -list -usage assert > fpv_vacuity.rpt
report_fv -list -vacuity {vacuous cond_non_vacuous inconclusive} >> fpv_vacuity.rpt

# 7.2 形式覆盖率：有没有 RTL 代码从来没被性质碰到过
#     前提是 read_file 时已加 -cov 插装（见第 1 节）。
#     compute_cov 会切换 appmode 到 COV，所以必须放在所有 FPV 步骤之后；
#     仍用 catch 兜住，避免偶发失败让整个脚本非零退出。
set_fml_appmode COV
cov_config -auto_scale
if {[catch {compute_cov} e]} {
  puts "WARN: compute_cov failed: $e"
} else {
  report_fv_coverage -list           > fpv_cov.rpt
  report_fv_coverage -list_uncovered > fpv_cov_uncovered.rpt
}

exit
