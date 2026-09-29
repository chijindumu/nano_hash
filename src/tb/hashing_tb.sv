module hashing_core_tb;
    timeunit 1ns;
    timeprecision 1ps;

    logic rst_n;
    logic new_block;
    logic done;    
    logic [31:0] k_t;
    logic [31:0] w_t;
    logic [255:0] digest;
    logic [5:0] round;
    logic load_block, next_round;
    logic digest_valid;
    int error_count;

    logic clk = 1'b1; 
    always #5 clk = ~clk;

    logic [31:0] k_t_stimulus [0:63];
    logic [31:0] block_0 [0:63];
    logic [31:0] block_1 [0:63];
    logic [31:0] block_2 [0:63];

    logic [31:0] current_w_buffer [0:63];

    hashing_core dut(.*);

    default clocking cb @(posedge clk);
        default input #1step output #1;
        output rst_n, new_block, done;
        input digest, round, load_block, next_round, digest_valid;
    endclocking

    always_comb begin
        k_t = k_t_stimulus[round];
        w_t = current_w_buffer[round];
    end

    initial begin
        $readmemh("constants.mem", k_t_stimulus);
        $readmemh("block_0.mem", block_0);
        $readmemh("block_1.mem", block_1);
        $readmemh("block_2.mem", block_2);

        cb.rst_n <= 1'b0;
        cb.new_block <= 1'b0;
        cb.done <= 1'b1;   // every test here is a single (final) block
        ##4         // wait for global reset
        cb.rst_n <= 1'b1;
        ##2;
    
        // block 0 xyz
        run_block(block_0, 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad);
        // block 1 empty
        run_block(block_1, 256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855);
        // block 2 abc
        run_block(block_2, 256'h71c480df93d6ae2f1efad1447c66c9525e316218cf51fc8d9ed832f2daf18b73);
        
        if(error_count == 0)
            $display("The three tests were successful!");
        else
            $display("%d Tests Failed!!", error_count);
        ##5;
        $finish();
    end

    task automatic run_block(input logic [31:0] block [0:63], input logic [255:0] expected_result);
        for (int i = 0; i < 64; i = i + 1) begin
            current_w_buffer[i] = block[i];
        end

        cb.rst_n <= 1'b0;
        repeat(2) @(cb);
        cb.rst_n <= 1'b1;
        @(cb);

        cb.new_block <= 1'b1;
        @(cb);
        cb.new_block <= 1'b0;
        do begin
            @(cb);
        end while (digest_valid !== 1'b1);

        if(digest == expected_result) begin
            $display("Test Passed, there are no errors");
        end else begin
            error_count++;
            $display("Test failed, expected %h, got %h", expected_result, digest);
        end
    endtask 


endmodule