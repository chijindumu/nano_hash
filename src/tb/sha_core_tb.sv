module sha_core_tb;
    timeunit 1ns;
    timeprecision 1ps;

    logic rst_n;
    logic [511:0] block;
    logic [255:0] digest;
    logic digest_valid;
    logic done;
    logic sha_valid; 
    logic scheduler_ready;
    logic [31:0] block_0 [0:15];
    logic [31:0] block_1 [0:15];
    logic [31:0] block_2 [0:15];
    logic [31:0] block_3 [0:15];
    logic [31:0] block_4 [0:15];


    logic [31:0] current_w_buffer [0:15];
    int error_count = 0;

    logic clk = 1'b1; 


    sha_core dut(.*);

    always #5 clk = ~clk;

    default clocking cb @(posedge clk);
        default input #1step output #1;
        input digest, digest_valid, scheduler_ready;
        output rst_n, done, sha_valid;
    endclocking

    always_comb begin
        for(int i = 0; i < 16; i++)
            block[511-(i*32) -: 32] = current_w_buffer[i];
    end

    initial begin
        $readmemh("block_0.mem", block_0);
        $readmemh("block_1.mem", block_1);
        $readmemh("block_2.mem", block_2);
        $readmemh("block_3.mem", block_3);
        $readmemh("block_4.mem", block_4);

        cb.rst_n  <= 1'b0;
        cb.done <= 1'b1;   // stay paused 
        cb.sha_valid <= 1'b0;
        ##4;               // wait for global reset
        cb.rst_n <= 1'b1;
        ##2;

        // block 0: abc
        run_block(block_0, 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad);
        // block 1: empty
        run_block(block_1, 256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855);
        // block 2: abcdefghijklmnopqrstuvwxyz
        run_block(block_2, 256'h71c480df93d6ae2f1efad1447c66c9525e316218cf51fc8d9ed832f2daf18b73);
        // block 3, 4: abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq;
        run_multiblock(block_3, block_4, 256'h248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1);

        if(error_count == 0)
            $display("The 4 tests passed!!");
        else
            $display("%d tests failed!", error_count);
            
        ##5;
        $finish();
    end

    task automatic run_block(input logic [31:0] r_block [0:15], input logic [255:0] expected);
        cb.done <= 1'b1;
        @(cb);

        for(int i = 0; i < 16; i++)
            current_w_buffer[i] = r_block[i];

        cb.done <= 1'b1;        // single-block message
        cb.sha_valid <= 1'b1;   // one-cycle block ready pulse
        @(cb);
        cb.sha_valid <= 1'b0;

        do begin
            @(cb);
        end while (digest_valid !== 1'b1);

        if(digest == expected) begin
           $display("Test passed!"); 
        end            
        else begin
            error_count++;
            $display("Test failed!, expected %h, got %h", expected, digest);
        end

        // pause 
        cb.done <= 1'b1;
        @(cb);

        cb.rst_n <= 1'b0;
        repeat(2) @(cb);
        cb.rst_n <= 1'b1;
        @(cb);
    endtask

    task automatic run_multiblock(
                                   input logic [31:0] blk_a [0:15],
                                   input logic [31:0] blk_b [0:15],
                                   input logic [255:0] expected
                                   );
        cb.done <= 1'b1;
        @(cb);

        for(int i = 0; i < 16; i++)
            current_w_buffer[i] = blk_a[i];

        cb.done <= 1'b0;        // not the last block
        cb.sha_valid <= 1'b1;   // one-cycle block ready pulse
        @(cb);
        cb.sha_valid <= 1'b0;

        // wait for the first block
        do begin
            @(cb);
        end while (digest_valid !== 1'b1);
 
        // swap in the second block and hand it to the core
        for(int i = 0; i < 16; i++)
            current_w_buffer[i] = blk_b[i];
        cb.done <= 1'b1;
        cb.sha_valid <= 1'b1;
        @(cb);
        cb.sha_valid <= 1'b0;
 
        // wait for the final digest
        do begin
            @(cb);
        end while (digest_valid !== 1'b1);
 
        if(digest == expected) begin
           $display("Test passed!");
        end
        else begin
            error_count++;
            $display("Test failed!, expected %h, got %h", expected, digest);
        end

        cb.done <= 1'b1;
        @(cb);

        cb.rst_n <= 1'b0;
        repeat(2) @(cb);
        cb.rst_n <= 1'b1;
        @(cb);
    endtask

endmodule
