// ---------- 标准 Round-Robin 仲裁器 ----------
// 特点: 单拍 req->gnt, 最坏等待 N-1, 无饿死
module arb_rr #(parameter int N = 8) (
  input  logic         clk, rst_n,
  input  logic [N-1:0] req,
  input  logic         upd,        // 1: 本拍 grant 被消费, 推进指针
  output logic [N-1:0] gnt,
  output logic         gnt_vld
);
  logic [N-1:0] mask;              // ptr 及之后为 1
  logic [N-1:0] req_hi, gnt_hi, gnt_lo;

  // --- 两个固定优先级编码器（低位优先）---
  assign req_hi = req & mask;
  assign gnt_hi = req_hi & (~req_hi + 1'b1);
  assign gnt_lo = req    & (~req    + 1'b1);

  assign gnt     = |req_hi ? gnt_hi : gnt_lo;   // 回绕
  assign gnt_vld = |req;

  // --- 指针更新: 指向被授权者的下一位 ---
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)            mask <= '1;                    // 复位后从 0 号开始
    else if (gnt_vld && upd) mask <= ~((gnt << 1) - 1'b1); // mask = ~(gnt*2-1)
  end
  // 说明: gnt=bit_k 时, (gnt<<1)-1 = 低 k+1 位全 1, 取反即 k+1 及以上为 1
  // 当 gnt=bit_{N-1} 时 (gnt<<1) 溢出为 0, mask 变全 1, 自动回绕到 0 号, 正确
endmodule
