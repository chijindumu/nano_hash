module uart_tx(
    output reg serial, tx_done,
    input wire clk, rst,
    //input wire baud_tick,
    input wire tx_trigger,
    input wire [7:0] data_in
);
    // state encoding
    localparam idle  = 2'b00,
              start = 2'b01,
              data  = 2'b10,
              stop  = 2'b11;

    // instantiating the baud rate generator
    wire baud_tick;
    baudgen baud_rate_generator(.baud_tick, .clk, .rst);

    reg [3:0] btick, btick_next;                // baud tick for oversampling
    reg [2:0] data_tick, data_tick_next;        // data bits register
    reg [7:0] data_reg, data_next;              // data register
    reg [1:0] current_state, next_state;        // state registers
    // state memory
    always @(posedge clk, negedge rst) begin: STATE_MEMORY
        if(!rst) begin
            current_state <= idle;
            data_reg <= 0;
            data_tick <= 0;
            btick <= 0;
        end else begin
            current_state <= next_state;
            data_reg <= data_next;
            data_tick <= data_tick_next;
            btick <= btick_next;
        end
    end
    // next state logic
    always @* begin: NEXT_STATE_LOGIC
        next_state = current_state;
        data_next = data_reg;
        data_tick_next = data_tick;
        btick_next = btick;

        case(current_state)
            idle: begin
                if(baud_tick) begin
                    if(tx_trigger) begin
                        data_next = data_in;
                        next_state = start;
                    end else begin 
                        next_state = idle;
                    end
                end
            end
            start: begin
                if(baud_tick) begin
                    if(btick == 15) begin
                        btick_next = 0;
                        next_state = data;
                    end else begin
                        btick_next = btick + 1;
                    end
                end
            end
            data: begin
                if(baud_tick) begin
                    if(btick == 15) begin
                        btick_next = 0;
                        data_next = data_reg >> 1;
                        if(data_tick == 7) begin
                            data_tick_next = 0;
                            next_state = stop;
                        end else begin
                            data_tick_next = data_tick + 1;
                        end
                    end else begin
                        btick_next = btick + 1;
                    end
                end
            end
            stop: begin
                if(baud_tick) begin 
                    if(btick == 15) begin
                        btick_next = 0; 
                        next_state = idle;
                    end else begin
                        btick_next = btick + 1;
                    end
                end
            end
            default: next_state = idle;
        endcase
    end
    // output logic
    always @* begin: OUTPUT
        case(current_state)
            idle: begin
                serial = 1'b1;
                tx_done = 1'b0;
            end 
            start: begin
                serial = 1'b0;
                tx_done = 1'b0;
            end 
            data: begin
                serial = data_reg[0];
                tx_done = 1'b0;
            end
            stop: begin
                serial = 1'b1;
                tx_done = 1'b1;
            end
            default: begin
                serial = 1'b1;
                tx_done = 1'b0;
            end
        endcase
    end
endmodule