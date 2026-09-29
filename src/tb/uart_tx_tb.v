`timescale 1ns/1ps
module uart_tx_tb;
    wire serial, tx_done;
    reg clk, rst;
    reg tx_trigger;
    reg [7:0] data_in;

    uart_tx dut(.serial, .tx_done, .clk, .rst, .tx_trigger, .data_in);

    // modelling the clk
    always #10 clk = ~clk;
    initial begin
        $dumpfile("uart_tx.vcd");
        $dumpvars(0, uart_tx_tb);

        {clk, rst, tx_trigger, data_in} = 0;
        repeat(2) @(posedge clk);       // wait for global reset
        rst = 1'b1;
        tx_trigger = 1'b0;
        data_in = 8'd108;
        while (!tx_done) begin
            @(posedge clk)
            #1;
            tx_trigger = 1'b1;
        end
        #1;
        $finish();
    end
endmodule