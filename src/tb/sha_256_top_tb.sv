`timescale 1ns/1ps

module sha_top_tb;

    // Clock and Reset
    logic        aclk = 0;
    logic        aresetn = 0;
    always #5 aclk = ~aclk; 

    // Master Interface (Digest Egress)
    logic        m_axis_tready;
    logic [31:0] m_axis_tdata;
    logic        m_axis_tvalid;
    logic        m_axis_tlast;

    // Slave Interface (Message Ingress)
    logic [31:0] s_axis_tdata;
    logic [3:0]  s_axis_tkeep;
    logic        s_axis_tvalid;
    logic        s_axis_tlast;
    logic        s_axis_tready;

    int error_count = 0;

    // DUT Instantiation
    sha_top dut (.*);

    // Helper Task: Send Byte Stream via S_AXIS
    task automatic send_stream(
        input byte msg[], 
        input bit  inject_bubbles = 1'b0
    );
        int total_bytes = msg.size();
        int num_words   = (total_bytes + 3) / 4;
        int byte_idx    = 0;

        // Handle empty message edge case (0 bytes)
        if (total_bytes == 0) begin
            @(posedge aclk);
            s_axis_tvalid <= 1'b1;
            s_axis_tdata  <= 32'h00000000;
            s_axis_tkeep  <= 4'b0000;
            s_axis_tlast  <= 1'b1;

            do begin
                @(posedge aclk);
            end while (!s_axis_tready);

            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
            return;
        end

        @(posedge aclk);  

        for (int w = 0; w < num_words; w++) begin
            logic [31:0] word_data = 32'd0;
            logic [3:0]  keep_mask = 4'b0000;
            bit is_last = (w == num_words - 1);

            // insert pipeline bubble to stress upstream handshaking
            if (inject_bubbles && ($urandom_range(0, 2) == 0)) begin
                s_axis_tvalid <= 1'b0;
                repeat ($urandom_range(1, 3)) @(posedge aclk);
            end

            // Pack up to 4 bytes (Big-Endian network order into 32-bit word)
            for (int b = 0; b < 4; b++) begin
                if (byte_idx < total_bytes) begin
                    word_data[31 - (b * 8) -: 8] = msg[byte_idx];
                    keep_mask[3 - b] = 1'b1;
                    byte_idx++;
                end
            end

            s_axis_tvalid <= 1'b1;
            s_axis_tdata  <= word_data;
            s_axis_tkeep  <= keep_mask;
            s_axis_tlast  <= is_last;

            // Wait for handshake
            do begin
                @(posedge aclk);
            end while (!s_axis_tready);
        end

        s_axis_tvalid <= 1'b0;
        s_axis_tlast  <= 1'b0;
        s_axis_tkeep  <= 4'b0000;
    endtask

    // Helper Task: Receive 8-Beat Digest via M_AXIS
    task automatic receive_digest(
        output logic [255:0] digest_out,
        input  bit           inject_backpressure = 1'b0
    );
        logic [31:0] words [0:7];

        for (int i = 0; i < 8; i++) begin
            m_axis_tready <= 1'b1;

            // deassert ready to force DUT to stall mid-transfer
            if (inject_backpressure && (i == 2 || i == 5)) begin
                m_axis_tready <= 1'b0;
                repeat ($urandom_range(2, 5)) @(posedge aclk);
                m_axis_tready <= 1'b1;
            end

            // Wait for valid beat
            do begin
                @(posedge aclk);
            end while (!(m_axis_tvalid && m_axis_tready));

            words[i] = m_axis_tdata;

            // Verify tlast asserts strictly on the 8th beat (index 7)
            if (i == 7 && !m_axis_tlast) begin
                $display("[ERROR] m_axis_tlast missing on beat 7!");
                error_count++;
            end else if (i < 7 && m_axis_tlast) begin
                $display("[ERROR] m_axis_tlast asserted prematurely on beat %0d!", i);
                error_count++;
            end
        end

        m_axis_tready <= 1'b0;
        digest_out = {words[0], words[1], words[2], words[3], 
                      words[4], words[5], words[6], words[7]};
    endtask

    // Helper Task: Run Test Case Check
    task automatic check_result(
        input string        test_name, 
        input logic [255:0] actual, 
        input logic [255:0] expected
    );
        if (actual === expected) begin
            $display("[PASS] %s\n       Digest: %064h", test_name, actual);
        end else begin
            $display("[FAIL] %s\n       Expected: %064h\n       Got:      %064h", 
                     test_name, expected, actual);
            error_count++;
        end
    endtask

    // Test Sequences Execution Block
    initial begin
        logic [255:0] digest_received;
        byte test_payload[];

        $dumpfile("waveform.vcd");
        $dumpvars(0, sha_top_tb);

        // Initialize signals
        s_axis_tdata  = 32'd0;
        s_axis_tkeep  = 4'b0000;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        m_axis_tready  = 1'b0;

        // Apply Reset
        aresetn = 1'b0;
        repeat (5) @(posedge aclk);
        aresetn = 1'b1;
        repeat (3) @(posedge aclk);

        // =====================================================================
        // SEQUENCE 1: Single-Block Non-Word Multiple ("abc", 3 bytes)
        // Verifies s_axis_tkeep handling (4'b1110) with partial 32-bit beat
        // =====================================================================
        $display("\n--- Starting Sequence 1: Single-Block Partial Word ('abc') ---");
        test_payload = '{byte'("a"), byte'("b"), byte'("c")};
        fork
            send_stream(test_payload);
            receive_digest(digest_received);
        join
        check_result("Seq 1 ('abc')", digest_received, 
                     256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad);

        // =====================================================================
        // SEQUENCE 2: Zero-Length Message ("")
        // Verifies zero-length message handling and boundary padding
        // =====================================================================
        $display("\n--- Starting Sequence 2: Empty Message (0 bytes) ---");
        test_payload = new[0];
        fork
            send_stream(test_payload);
            receive_digest(digest_received);
        join
        check_result("Seq 2 (empty string)", digest_received, 
                     256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855);

        // =====================================================================
        // SEQUENCE 3: Multi-Block Boundary Condition (56 Bytes)
        // 56 bytes fills block 0 up to word 14, forcing padding into block 1.
        // Tests internal message chaining across multiple 512-bit blocks.
        // =====================================================================
        $display("\n--- Starting Sequence 3: Multi-Block Boundary (56 bytes) ---");
        test_payload = '{
            "a","b","c","d","b","c","d","e","c","d","e","f","d","e","f","g",
            "e","f","g","h","f","g","h","i","g","h","i","j","h","i","j","k",
            "i","j","k","l","j","k","l","m","k","l","m","n","l","m","n","o",
            "m","n","o","p","n","o","p","q"
        };
        fork
            send_stream(test_payload);
            receive_digest(digest_received);
        join
        check_result("Seq 3 (56-byte 2-block)", digest_received, 
                     256'h248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1);

        // =====================================================================
        // SEQUENCE 4: Ingress Pipeline Bubbles (s_axis_tvalid Stalls)
        // Injects randomized valid drops to ensure the padder does not corrupt
        // intermediate state during stream delays.
        // =====================================================================
        $display("\n--- Starting Sequence 4: Upstream Flow-Control Bubbles ---");
        test_payload = '{
            "a","b","c","d","e","f","g","h","i","j","k","l","m",
            "n","o","p","q","r","s","t","u","v","w","x","y","z"
        };
        fork
            send_stream(test_payload, .inject_bubbles(1'b1));
            receive_digest(digest_received);
        join
        check_result("Seq 4 (26 bytes with ingress bubbles)", digest_received, 
                     256'h71c480df93d6ae2f1efad1447c66c9525e316218cf51fc8d9ed832f2daf18b73);

        // =====================================================================
        // SEQUENCE 5: Egress Backpressure (m_axis_tready Stalls)
        // Drops m_axis_tready at beats 2 and 5 to verify the output serializer
        // holds tdata stable and honors AXI-Stream stall rules.
        // =====================================================================
        $display("\n--- Starting Sequence 5: Downstream Backpressure Stalls ---");
        test_payload = '{byte'("a"), byte'("b"), byte'("c")};
        fork
            send_stream(test_payload);
            receive_digest(digest_received, .inject_backpressure(1'b1));
        join
        check_result("Seq 5 ('abc' with egress stalls)", digest_received, 
                     256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad);

        // Final Assessment
        repeat (10) @(posedge aclk);
        if (error_count == 0) begin
            $display("\n=======================================================");
            $display("  ALL 5 SEQUENCES PASSED SUCCESSFULLY");
            $display("=======================================================\n");
        end else begin
            $display("\n=======================================================");
            $display("  VERIFICATION FAILED: %0d ERRORS DETECTED", error_count);
            $display("=======================================================\n");
        end

        $finish();
    end

endmodule