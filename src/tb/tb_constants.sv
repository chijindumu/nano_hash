`timescale 1ns / 1ps

module tb_constants;

    logic [5:0] round_tb;
    logic [31:0] k_tb;
    int error_count;

    sha_256_constants uut(
        .round(round_tb),
        .k_t(k_tb)
    );

    logic [31:0] expected_k [0:63];

    initial begin
        $dumpfile("sha_constants.vcd");
        $dumpvars(0, tb_constants);

        // NIST SHA-256 Constants

        $readmemh("constants.mem", expected_k);
        
        $display("Starting SHA-256 Constants ROM Test...");
        error_count = 0;

        // Exhaustive test of all 64 valid rounds
        for (int i = 0; i < 64; i++) begin
            round_tb = i;
            #5; 

            // Self-checking assertion
            if (k_tb !== expected_k[i]) begin
                $error("Mismatch at round %0d! Expected: %h, Got: %h", i, expected_k[i], k_tb);
                error_count++;
            end
        end

        if (error_count == 0) begin
            $display("SUCCESS: All 64 constants and default case matched!");
        end else begin
            $display("FAILED with %0d errors. Please check your ROM array.", error_count);
        end

        $finish;
    end

endmodule