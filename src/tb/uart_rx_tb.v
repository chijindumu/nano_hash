`timescale 1ns/1ps
module uart_rx_tb;
    wire [7:0] data_out;
    wire rx_done;
    reg clk, rst, serial;
    // instantiate design module
    uart_rx dut(.data_out, .rx_done, .clk, .rst, .serial);
    // modelling clk
    always #10 clk = ~clk;
    initial begin
        $dumpfile("uart_rx.vcd");
        $dumpvars(0, uart_rx_tb);
        // initial values
        {clk, rst} = 0;
        serial = 1;
        repeat(2) @(posedge clk);       // wait for global clock reset
        rst = 1'b1;
        repeat(325) begin
            @(posedge clk);
            #1;
            serial = 1;
        end
        repeat(2) begin
            // count 325 times for each baud tick and multiply by 16 for the oversampling
            // start bit
            repeat(5200) begin
                @(posedge clk);
                #1;
                serial = 0;
            end
            // data bits
            // 8 bit data
            // 0 0 1 1 0 1 1 0 on serial line in lsb
            // actual data is 0 1 1 0 1 1 0 0 = 6C
            repeat(10400) begin       // 2 0s
                @(posedge clk);
                #1;
                serial = 0;
            end
            repeat(10400) begin       // 2 1s
                @(posedge clk);
                #1;
                serial = 1;
            end
            repeat(5200) begin       // 1 0s
                @(posedge clk);
                #1;
                serial = 0;
            end
            repeat(10400) begin       // 2 1s
                @(posedge clk);
                #1;
                serial = 1;
            end
            repeat(5200) begin       // 1 0s
                @(posedge clk);
                #1;
                serial = 0;
            end
        end 
        // output in hex
        // 00 00 80 C0 60 B0 D8 6C
        #1;
        $finish();
    end
endmodule