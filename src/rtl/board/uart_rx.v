module uart_rx(
    output wire [7:0] data_out,
    output reg rx_done,
    input wire clk, rst,
    //input wire baud_tick,
    input wire serial
);
    // state encoding
    localparam idle  = 2'b00,
              start = 2'b01,
              data  = 2'b10,
              stop  = 2'b11;


    // instantiating the baud rate generator
    wire baud_tick;
    baudgen baud_rate_generator(.baud_tick, .clk, .rst);

    // current and next state registes
    reg [1:0] current_state, next_state;        // state registers
    reg [7:0] data_reg, data_next;              // data registers
    reg [3:0] btick, btick_next;                // sampling rate tick
    reg [2:0] data_tick, data_tick_next;        // data bit registers

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
        rx_done = 1'b0;
        case(current_state)
            idle: begin
                if(baud_tick) begin
                    if(!serial) begin
                        next_state = start;
                    end else begin
                        next_state = idle;
                    end 
                end
            end
            start: begin
                if(baud_tick) begin
                    if(btick == 7) begin
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
                        data_next = {serial, data_reg[7:1]};
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
                        rx_done = 1'b1;        // output high
                    end else begin
                        btick_next = btick + 1;
                    end    
                end
            end
            default: next_state = idle;
        endcase
    end

    // output logic
    assign data_out = data_reg;
endmodule