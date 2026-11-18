// ============================================================
// arb_fpv.sv : 仲裁器形式验证属性文件（bind 式，仿真/形式通用）
// ============================================================
`ifndef SYNTHESIS

// ------------------------------------------------------------
// (A) 通用仲裁器性质：三铁律 + 有界无饿死（对称性归约版）
// ------------------------------------------------------------
module arb_fpv_core #(
  parameter int N     = 8,
  parameter int BOUND = 7      // RR: N-1；WRR/DWRR: ΣW
) (
  input logic         clk, rst_n,
  input logic [N-1:0] req, gnt,
  input logic         gnt_vld, upd
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // ---- 铁律 1/2/3（秒级 proven）----
  ap_onehot : assert property ($onehot0(gnt));
  ap_subset : assert property ((gnt & ~req) == '0);
  ap_vld    : assert property (gnt_vld == |gnt);
  ap_noidle : assert property ((|req) |-> gnt_vld);

  // ---- 对称性归约：符号化冻结索引 ----
  bit [$clog2(N)-1:0] SI;
  am_si_stable : assume property ($stable(SI));
  am_si_range  : assume property (SI < N);

  // 持续请求必在 BOUND 拍内被服务（有界 liveness）
  ap_bound : assert property (
    (req[SI] && !gnt[SI]) |-> ##[0:BOUND] gnt[SI]);

  // ---- cover：确认状态机真的走到过有意思的地方 ----
  cp_all_req  : cover property (req == '1);
  cp_single   : cover property ($onehot(req) && gnt_vld);
  cp_wrap     : cover property (gnt[N-1] ##1 gnt[0]);   // 指针回卷
endmodule

// ------------------------------------------------------------
// (B) Round-Robin 专有：mask 更新正确性
// ------------------------------------------------------------
module rr_fpv #(parameter int N = 8) (
  input logic         clk, rst_n, upd, gnt_vld,
  input logic [N-1:0] req, gnt, mask
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // mask 必须是「赢家之后」的那段连续 1，这是 RR 的全部奥秘
  // 注意 gnt[N-1] 时 (gnt<<1) 溢出，必须回卷成全 1，否则退化成固定优先级
  function automatic logic [N-1:0] exp_mask(logic [N-1:0] g);
    return (g[N-1]) ? {N{1'b1}} : ~(({1'b0,g[N-2:0]} << 1) - 1);
  endfunction

  ap_mask_upd : assert property (
    (upd && gnt_vld) |=> (mask == exp_mask($past(gnt))));

  ap_mask_hold : assert property (
    (!upd || !gnt_vld) |=> $stable(mask));

  // 掩码后有请求时，必须从掩码域里选，不能回头抢低编号
  ap_mask_prio : assert property (
    |(req & mask) |-> |(gnt & mask));
endmodule

// ------------------------------------------------------------
// (C) Age Matrix：反对称 + 传递性（随机仿真最难覆盖，形式最拿手）
// ------------------------------------------------------------
module age_fpv #(parameter int N = 8) (
  input logic           clk, rst_n,
  input logic [N-1:0]   ins, req, gnt,
  input logic [N-1:0][N-1:0] M       // M[i][j]=1 表示 i 比 j 老
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // 反对称：任意一对不能互相都更老，也不能互相都更新
  // 用符号化索引代替 generate 出 N*(N-1)/2 条断言
  bit [$clog2(N)-1:0] AI, AJ, AK;
  am_idx_stable : assume property ($stable(AI) && $stable(AJ) && $stable(AK));
  am_idx_range  : assume property (AI < N && AJ < N && AK < N);
  am_idx_distinct: assume property (AI != AJ && AJ != AK && AI != AK);

  ap_antisym : assert property (M[AI][AJ] != M[AJ][AI]);

  ap_trans   : assert property (
    (M[AI][AJ] && M[AJ][AK]) |-> M[AI][AK]);

  // 对角线恒为 0（自己不比自己老）
  ap_diag    : assert property (M[AI][AI] == 1'b0);

  // 赢家唯一：选出的必须是请求集合里最老的那个
  ap_oldest  : assert property (
    (gnt[AI] && req[AJ]) |-> M[AI][AJ]);

  // ★ 不要写成 assume！插入 one-hot 是设计责任，必须 assert 出来
  ap_ins_onehot : assert property ($onehot0(ins));
endmodule

// ------------------------------------------------------------
// (D) Credit / 令牌桶：守恒不变式 + 不溢出/不下溢
// ------------------------------------------------------------
module credit_fpv #(
  parameter int W     = 8,
  parameter int MAXC  = 16,
  parameter int BURST = 32
) (
  input logic         clk, rst_n,
  input logic         send, ret,
  input logic [W-1:0] credit, tokens,
  input logic [W-1:0] sent_cnt, ret_cnt
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // 守恒式：一条式子证完所有 send/ret 交错场景
  ap_conserve : assert property (sent_cnt - ret_cnt == MAXC - credit);

  // 边界：不下溢、不溢出
  ap_no_under : assert property (send |-> credit > 0);
  ap_no_over  : assert property (credit <= MAXC);
  ap_tok_cap  : assert property (tokens <= BURST);

  // 减法前保证被减数够大（AEP 也会自动抽出这条）
  ap_sub_safe : assert property (send |-> tokens >= 1);

  // 无 credit 时绝不能发（协议级死锁的根源）
  ap_gate     : assert property ((credit == 0) |-> !send);
endmodule

// ------------------------------------------------------------
// (E) DWRR：deficit 不溢出 + quantum >= MTU
// ------------------------------------------------------------
module dwrr_fpv #(
  parameter int W    = 12,
  parameter int QMAX = 1500,
  parameter int LMAX = 1500
) (
  input logic         clk, rst_n,
  input logic [W-1:0] deficit, quantum, pkt_len
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // 位宽证明：deficit 最坏值 = quantum + 刚补充未用完的余量
  ap_def_bound : assert property (deficit <= QMAX + LMAX);

  // 配置合法性：quantum < MTU 会导致该队列永远发不出大包（饿死）
  ap_quantum   : assert property (quantum >= LMAX);

  // deficit 不能变负（无符号下溢会变成巨大值，表现为该队列狂发）
  ap_def_nonneg: assert property (
    (pkt_len > deficit) |-> $stable(deficit) or deficit <= QMAX + LMAX);
endmodule

// ============================================================
// bind 语句：RTL 零改动挂载
// ============================================================
bind rr_arb   arb_fpv_core #(.N(8), .BOUND(7)) u_core (
  .clk(clk), .rst_n(rst_n), .req(req), .gnt(gnt),
  .gnt_vld(gnt_vld), .upd(upd));

bind rr_arb   rr_fpv #(.N(8)) u_rr (
  .clk(clk), .rst_n(rst_n), .upd(upd), .gnt_vld(gnt_vld),
  .req(req), .gnt(gnt), .mask(mask_q));

bind iq_sched age_fpv #(.N(16)) u_age (
  .clk(clk), .rst_n(rst_n), .ins(alloc_vec),
  .req(ready_vec), .gnt(issue_vec), .M(age_mtx));

bind lnk_tx   credit_fpv #(.W(8), .MAXC(16), .BURST(32)) u_cr (
  .clk(clk), .rst_n(rst_n), .send(tx_vld), .ret(cr_ret),
  .credit(credit_q), .tokens(token_q),
  .sent_cnt(dbg_sent), .ret_cnt(dbg_ret));

`endif
