module message_tb;
    timeunit 1ns;
    timeprecision 100ps;
    
    logic rst_n;
    logic [511:0] block;
    logic load_block, next_round;
    logic [31:0] w_t;
    logic scheduler_ready;

    logic clk = 1'b1;

    logic [31:0] expected_results [0:63];

    message_scheduler dut(.*);

    always #5 clk = ~clk;

    default clocking cb @(posedge clk);
        default input #1step output #4;
        output rst_n, block, load_block, next_round;
        input w_t, scheduler_ready;
    endclocking

    initial begin
        int error; 
        $readmemh("message.mem", expected_results);

        cb.rst_n <= 0; 
        cb.block <= '0;
        cb.load_block <= 0; 
        cb.next_round <= 0;
        // wait for global reset

        ##3; cb.rst_n <= 1; 
        cb.block <= {16{32'd7000}};
        // load block
        cb.load_block <= 1; 
        cb.next_round <= 0;
        ##1; cb.load_block <= 0; // drop line

        ##2; error = error_check(cb.w_t, 32'h00001b58);
        ##1; errors(error);      // print error status

        // next round
        for(int i = 1; i < 64; i = i + 1) begin
            cb.next_round <= 1;
            ##1; cb.next_round <= 0;    // drop the line
            ##2; error = error_check(cb.w_t, expected_results[i]);
            ##1; errors(error);          // print error status
        end

        ##3;
        $finish();
    end

    function int error_check(input logic [31:0] result, expected);
        int error;
        if(result !== expected) begin
            $display("Error! expected %h, got %h", expected, result);
            error++;
        end
        error_check = error;
    endfunction

    function void errors(input int error);
        if(error == 0)
            $display("Test passed! there are no errors");
        else 
            $display("Test failed, there are %d, errors", error);
    endfunction

endmodule
