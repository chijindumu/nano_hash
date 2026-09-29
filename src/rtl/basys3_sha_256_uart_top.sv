// =============================================================================
// basys3_sha256_uart_top.sv
//
// Basys3 top level: lets you type a message into TeraTerm, press Enter, and
// get the SHA-256 hash of that message printed back as 64 hex characters.
//
// Wraps:
//   - sha_top          (sha_256_top.sv)   : AXI4-Stream SHA-256 core
//   - uart_rx           (uart_rx.v)        : 8N1 UART receiver, 16x oversample
//   - uart_tx           (uart_tx.v)        : 8N1 UART transmitter
// uart_rx/uart_tx each instantiate their own `baudgen` (baudrate_gen.v)
// internally with the default samplingrate=326 -> 19200 baud @ 100 MHz clk.
// Set TeraTerm to 19200 baud, 8 data bits, no parity, 1 stop bit, no flow
// control, and turn OFF local echo (this design echoes typed characters
// itself so you can see what you're typing and use Backspace to correct it).
//
// Pins (Basys3 rev B/C/D/E, Digilent master XDC names):
//   clk  -> W5   (100 MHz onboard oscillator)
//   btnC -> U18  (center pushbutton, active-high system reset)
//   RsRx -> B18  (USB-UART bridge TX -> FPGA RX)
//   RsTx -> A18  (FPGA TX -> USB-UART bridge RX)
//   led[2:0] -> U16, E19, U19 (status only, optional)
// =============================================================================

module basys3_sha256_uart_top (
    input  logic       clk,
    input  logic       btnC,
    input  logic       RsRx,
    output logic       RsTx,
    output logic [2:0] led
);
    timeunit 1ns;
    timeprecision 1ps;

    // -------------------------------------------------------------------
    // Reset synchronizer: btnC is an async, active-high pushbutton.
    // sha_top/uart_rx/uart_tx all want a synchronous, ACTIVE-LOW reset.
    // -------------------------------------------------------------------
    logic [1:0] rst_sync;
    logic       rst_n;

    always_ff @(posedge clk) begin
        rst_sync <= {rst_sync[0], btnC};
    end
    assign rst_n = ~rst_sync[1];

    // -------------------------------------------------------------------
    // UART instances (baud rate fixed by their internal baudgen default:
    // 100 MHz / (19200*16) = 326 -> 19200 baud)
    // -------------------------------------------------------------------
    logic [7:0] rx_data;
    logic       rx_done;

    uart_rx u_uart_rx (
        .data_out (rx_data),
        .rx_done  (rx_done),
        .clk      (clk),
        .rst      (rst_n),
        .serial   (RsRx)
    );

    logic [7:0] tx_data;
    logic       tx_trigger;
    logic       tx_done;

    uart_tx u_uart_tx (
        .serial     (RsTx),
        .tx_done    (tx_done),
        .clk        (clk),
        .rst        (rst_n),
        .tx_trigger (tx_trigger),
        .data_in    (tx_data)
    );

    // -------------------------------------------------------------------
    // TX byte-sender: uart_tx exposes no "busy"/"idle" port, only
    // tx_trigger (in) and tx_done (out, high only during the stop bit).
    // tx_trigger is sampled by uart_tx only while it is idle AND a
    // baud_tick happens to land in that same cycle, so a request must be
    // held long enough to guarantee at least one baud_tick occurs
    // (baud_tick repeats every 326 clk cycles here) before being dropped.
    // "busy" is tracked locally and cleared on the falling edge of
    // tx_done, which marks the return to the idle state.
    // -------------------------------------------------------------------
    localparam int HOLD_CYCLES = 700; // > 2 * 326, safely spans a baud_tick

    logic        tx_req;      // pulse: request to send tx_byte_in
    logic [7:0]  tx_byte_in;
    logic        tx_ready;    // 1 = transmitter idle, safe to request

    logic        tx_hold;
    logic [9:0]  tx_hold_cnt;
    logic        tx_busy;
    logic        tx_done_q;

    assign tx_trigger = tx_hold;
    assign tx_ready    = ~tx_busy;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_hold     <= 1'b0;
            tx_hold_cnt <= '0;
            tx_busy     <= 1'b0;
            tx_done_q   <= 1'b0;
            tx_data     <= 8'h00;
        end else begin
            tx_done_q <= tx_done;

            if (tx_req && tx_ready) begin
                tx_data     <= tx_byte_in;
                tx_hold     <= 1'b1;
                tx_hold_cnt <= '0;
                tx_busy     <= 1'b1;
            end else if (tx_hold) begin
                tx_hold_cnt <= tx_hold_cnt + 1'b1;
                if (tx_hold_cnt == HOLD_CYCLES - 1) begin
                    tx_hold <= 1'b0;
                end
            end

            if (tx_busy && tx_done_q && !tx_done) begin
                tx_busy <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------
    // sha_top AXI4-Stream connections
    // -------------------------------------------------------------------
    logic [31:0] s_axis_tdata;
    logic [3:0]  s_axis_tkeep;
    logic        s_axis_tvalid;
    logic        s_axis_tlast;
    logic        s_axis_tready;

    logic [31:0] m_axis_tdata;
    logic        m_axis_tvalid;
    logic        m_axis_tlast;
    logic        m_axis_tready;

    sha_top u_sha_top (
        .aclk          (clk),
        .aresetn       (rst_n),
        .m_axis_tready (m_axis_tready),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tlast  (m_axis_tlast),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tkeep  (s_axis_tkeep),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tlast  (s_axis_tlast),
        .s_axis_tready (s_axis_tready)
    );

    // -------------------------------------------------------------------
    // Message capture buffer
    // -------------------------------------------------------------------
    localparam int MAX_MSG_BYTES = 256; // 256 chars = up to 4 SHA-256 blocks

    logic [7:0] msg_mem [0:MAX_MSG_BYTES-1];
    logic [8:0] byte_count; // 0..256

    // -------------------------------------------------------------------
    // Fixed strings / hex conversion helpers
    // -------------------------------------------------------------------
    logic [31:0] digest_words [0:7];

    function automatic logic [7:0] prompt_char(input logic [1:0] idx);
        case (idx)
            2'd0: prompt_char = 8'h0D;
            2'd1: prompt_char = 8'h0A;
            2'd2: prompt_char = ">";
            default: prompt_char = " ";
        endcase
    endfunction
    localparam int PROMPT_LEN = 4;

    function automatic logic [7:0] label_char(input logic [3:0] idx);
        case (idx)
            4'd0: label_char = 8'h0D;
            4'd1: label_char = 8'h0A;
            4'd2: label_char = "S";
            4'd3: label_char = "H";
            4'd4: label_char = "A";
            4'd5: label_char = "-";
            4'd6: label_char = "2";
            4'd7: label_char = "5";
            4'd8: label_char = "6";
            4'd9: label_char = ":";
            default: label_char = " "; // idx == 10
        endcase
    endfunction
    localparam int LABEL_LEN = 11;

    function automatic logic [7:0] bs_erase_char(input logic [1:0] idx);
        case (idx)
            2'd0: bs_erase_char = 8'h08; // backspace
            2'd1: bs_erase_char = " ";   // blank out the character
            default: bs_erase_char = 8'h08; // backspace again -> cursor back
        endcase
    endfunction
    localparam int BS_LEN = 3;

    function automatic logic [7:0] nibble_to_ascii(input logic [3:0] nib);
        // 0-9 -> '0'..'9' (48+n); 10-15 -> 'a'..'f' (87+n, since 'a' = 97)
        nibble_to_ascii = (nib < 4'd10) ? (8'd48 + {4'b0, nib})
                                         : (8'd87 + {4'b0, nib});
    endfunction

    function automatic logic [7:0] hex_char(input logic [5:0] idx);
        logic [2:0] word_num;
        logic [2:0] nib_num;
        logic [31:0] w;
        begin
            word_num = idx[5:3];
            nib_num  = idx[2:0];
            w = digest_words[word_num];
            hex_char = nibble_to_ascii(w[31 - 4*nib_num -: 4]);
        end
    endfunction
    localparam int HEX_LEN = 64;

    // -------------------------------------------------------------------
    // Main control FSM
    // -------------------------------------------------------------------
    typedef enum logic [3:0] {
        S_PRINT_PROMPT,
        S_WAIT_INPUT,
        S_ECHO_CHAR,
        S_ECHO_BS,
        S_ENTER_NL,
        S_STREAM_INIT,
        S_STREAM_WORD,
        S_WAIT_DIGEST,
        S_PRINT_LABEL,
        S_PRINT_HEX
    } state_t;

    state_t      current_state, next_state;
    logic [6:0]  word_idx, total_words;
    logic [3:0]  last_word_tkeep;
    logic [3:0]  digest_word_idx;
    logic [6:0]  print_idx;
    logic [7:0]  echo_char;

    // word packer: builds s_axis_tdata for a given word index from msg_mem
    function automatic logic [31:0] pack_word(input logic [6:0] widx);
        logic [7:0] b0, b1, b2, b3;
        logic [8:0] base;
        begin
            base = {widx, 2'b00}; // widx*4
            b0 = (base   < byte_count) ? msg_mem[base]   : 8'h00;
            b1 = (base+1 < byte_count) ? msg_mem[base+1] : 8'h00;
            b2 = (base+2 < byte_count) ? msg_mem[base+2] : 8'h00;
            b3 = (base+3 < byte_count) ? msg_mem[base+3] : 8'h00;
            pack_word = {b0, b1, b2, b3};
        end
    endfunction

    // ---- sequential: state + datapath registers ----
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state   <= S_PRINT_PROMPT;
            byte_count      <= '0;
            word_idx        <= '0;
            total_words     <= '0;
            last_word_tkeep <= 4'b0000;
            digest_word_idx <= '0;
            print_idx       <= '0;
            echo_char       <= 8'h00;
            for (int i = 0; i < MAX_MSG_BYTES; i++) msg_mem[i] <= 8'h00;
            for (int i = 0; i < 8; i++) digest_words[i] <= 32'h0;
        end else begin
            current_state <= next_state;

            unique case (current_state)

                // ---- capture input ----
                S_WAIT_INPUT: begin
                    if (rx_done) begin
                        if (rx_data == 8'h0D || rx_data == 8'h0A) begin
                            print_idx <= 7'd0;
                        end else if (rx_data == 8'h08 || rx_data == 8'h7F) begin
                            if (byte_count > 0) begin
                                byte_count <= byte_count - 1'b1;
                                print_idx  <= 7'd0;
                            end
                        end else if (byte_count < MAX_MSG_BYTES) begin
                            msg_mem[byte_count] <= rx_data;
                            byte_count          <= byte_count + 1'b1;
                            echo_char           <= rx_data;
                        end
                    end
                end

                S_ECHO_CHAR: begin
                    if (tx_ready) begin
                        // single byte, transition handled in next_state logic
                    end
                end

                S_ECHO_BS, S_ENTER_NL, S_PRINT_LABEL, S_PRINT_HEX, S_PRINT_PROMPT: begin
                    if (tx_ready) begin
                        print_idx <= print_idx + 1'b1;
                    end
                end

                S_STREAM_INIT: begin
                    if (byte_count == 0) begin
                        total_words     <= 7'd1;
                        last_word_tkeep <= 4'b0000;
                    end else if (byte_count[1:0] == 2'b00) begin
                        total_words     <= byte_count[8:2];
                        last_word_tkeep <= 4'b1111;
                    end else begin
                        total_words     <= byte_count[8:2] + 7'd1;
                        case (byte_count[1:0])
                            2'd1:    last_word_tkeep <= 4'b1000;
                            2'd2:    last_word_tkeep <= 4'b1100;
                            default: last_word_tkeep <= 4'b1110; // 2'd3
                        endcase
                    end
                    word_idx        <= 7'd0;
                    digest_word_idx <= 4'd0;
                end

                S_STREAM_WORD: begin
                    if (s_axis_tready) begin
                        if (word_idx != total_words - 1'b1) begin
                            word_idx <= word_idx + 1'b1;
                        end
                    end
                end

                S_WAIT_DIGEST: begin
                    if (m_axis_tvalid && m_axis_tready) begin
                        digest_words[digest_word_idx] <= m_axis_tdata;
                        digest_word_idx <= digest_word_idx + 1'b1;
                        if (m_axis_tlast) begin
                            print_idx <= 7'd0;
                        end
                    end
                end

                default: ;
            endcase

            // byte_count is cleared exactly once, when leaving the prompt
            // (covers both the very first prompt after reset and every
            // post-hash prompt), so a fresh message always starts at index 0
            if (current_state == S_PRINT_PROMPT && tx_ready &&
                print_idx == PROMPT_LEN - 1) begin
                byte_count <= '0;
            end

            // Every print sequence (echo-BS, newline, label, hex, prompt) must
            // start at index 0. Clearing on any state change fixes the case
            // where print_idx carried over (e.g. label ended at 11, so the hex
            // string started at character 11). Placed last so it wins over the
            // increment above on the cycle a sequence finishes.
            if (next_state != current_state) begin
                print_idx <= 7'd0;
            end
        end
    end

    // ---- combinational: next-state logic ----
    always_comb begin
        next_state = current_state;
        unique case (current_state)
            S_PRINT_PROMPT: if (tx_ready && print_idx == PROMPT_LEN - 1) next_state = S_WAIT_INPUT;
            S_WAIT_INPUT: begin
                if (rx_done) begin
                    if (rx_data == 8'h0D || rx_data == 8'h0A) next_state = S_ENTER_NL;
                    else if ((rx_data == 8'h08 || rx_data == 8'h7F) && byte_count > 0) next_state = S_ECHO_BS;
                    else if (rx_data != 8'h08 && rx_data != 8'h7F && byte_count < MAX_MSG_BYTES) next_state = S_ECHO_CHAR;
                end
            end
            S_ECHO_CHAR:  if (tx_ready) next_state = S_WAIT_INPUT;
            S_ECHO_BS:    if (tx_ready && print_idx == BS_LEN - 1)    next_state = S_WAIT_INPUT;
            S_ENTER_NL:   if (tx_ready && print_idx == 7'd1)          next_state = S_STREAM_INIT;
            S_STREAM_INIT: next_state = S_STREAM_WORD;
            S_STREAM_WORD: if (s_axis_tready && word_idx == total_words - 1'b1) next_state = S_WAIT_DIGEST;
            S_WAIT_DIGEST: if (m_axis_tvalid && m_axis_tready && m_axis_tlast) next_state = S_PRINT_LABEL;
            S_PRINT_LABEL: if (tx_ready && print_idx == LABEL_LEN - 1) next_state = S_PRINT_HEX;
            S_PRINT_HEX:   if (tx_ready && print_idx == HEX_LEN - 1)   next_state = S_PRINT_PROMPT;
            default: next_state = S_PRINT_PROMPT;
        endcase
    end

    // ---- combinational: TX request + outputs ----
    always_comb begin
        tx_req        = 1'b0;
        tx_byte_in    = 8'h00;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        s_axis_tdata  = 32'h0;
        s_axis_tkeep  = 4'b0000;
        m_axis_tready = 1'b0;

        unique case (current_state)
            S_PRINT_PROMPT: begin
                if (tx_ready) begin
                    tx_req     = 1'b1;
                    tx_byte_in = prompt_char(print_idx[1:0]);
                end
            end
            S_ECHO_CHAR: begin
                if (tx_ready) begin
                    tx_req     = 1'b1;
                    tx_byte_in = echo_char;
                end
            end
            S_ECHO_BS: begin
                if (tx_ready) begin
                    tx_req     = 1'b1;
                    tx_byte_in = bs_erase_char(print_idx[1:0]);
                end
            end
            S_ENTER_NL: begin
                if (tx_ready) begin
                    tx_req     = 1'b1;
                    tx_byte_in = prompt_char(print_idx[1:0]); // idx 0=CR,1=LF
                end
            end
            S_STREAM_WORD: begin
                s_axis_tvalid = 1'b1;
                s_axis_tdata  = pack_word(word_idx);
                s_axis_tkeep  = (word_idx == total_words - 1'b1) ? last_word_tkeep : 4'b1111;
                s_axis_tlast  = (word_idx == total_words - 1'b1);
            end
            S_WAIT_DIGEST: begin
                m_axis_tready = 1'b1;
            end
            S_PRINT_LABEL: begin
                if (tx_ready) begin
                    tx_req     = 1'b1;
                    tx_byte_in = label_char(print_idx[3:0]);
                end
            end
            S_PRINT_HEX: begin
                if (tx_ready) begin
                    tx_req     = 1'b1;
                    tx_byte_in = hex_char(print_idx[5:0]);
                end
            end
            default: ;
        endcase
    end

    // -------------------------------------------------------------------
    // Status LEDs (optional, purely cosmetic)
    // -------------------------------------------------------------------
    assign led[0] = (current_state != S_WAIT_INPUT) && (current_state != S_PRINT_PROMPT);
    assign led[1] = (current_state == S_STREAM_WORD) || (current_state == S_WAIT_DIGEST);
    assign led[2] = (current_state == S_PRINT_LABEL) || (current_state == S_PRINT_HEX);

endmodule