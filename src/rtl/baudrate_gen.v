module baudgen #(parameter samplingrate = 326)(
    output reg baud_tick,
    input wire clk, rst         
);
    // baud_tick is 9-bit to hold 326
    // since baud rate = 19200 and clk is 100Mhz; 
    //with 16x sampling; sampling rate = (100M) / (19200 * 16) = 326
    
    reg [8:0] rbaud_tick;
    always @(posedge clk, negedge rst) begin
        if(!rst) begin
            rbaud_tick <= 0;
            baud_tick <= 0;
        end else if (rbaud_tick == (samplingrate - 1)) begin
            rbaud_tick <= 0;
            baud_tick <= 1'b1;
        end else begin
            rbaud_tick <= rbaud_tick + 1;
            baud_tick <= 1'b0;
        end
    end
endmodule