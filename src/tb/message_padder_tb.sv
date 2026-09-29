module message_padder_tb;
    timeunit 1ns;
    timeprecision 1ps;

    logic aresetn;
    logic [31:0] s_axis_tdata;
    logic [3:0] s_axis_tkeep;
    logic s_axis_tvalid;
    logic s_axis_tlast;
    logic scheduler_ready;

    logic s_axis_tready;
    logic [511:0] block;
    logic sha_valid;
    logic done;
    
    logic [39:0] axis_stimulus [0:99];
    logic [511:0] expected_result [0:16];

    logic aclk = 1'b1;
    int error_count = 0;
    int j = 0;

    message_padder dut(.*);

    always #5 aclk = ~aclk;

    function automatic logic [3:0] normalize_keep(input logic [3:0] k, input int idx);
        case (k)
            4'b0001: normalize_keep = 4'b1000;
            4'b0011: normalize_keep = 4'b1100;
            4'b0111: normalize_keep = 4'b1110;
            default: normalize_keep = k;
        endcase
        
    endfunction

    default clocking cb @(posedge aclk);
        default input #1step output #1;
        input s_axis_tready, block, sha_valid, done;
        output aresetn, s_axis_tdata, s_axis_tkeep, s_axis_tvalid, s_axis_tlast;
    endclocking

    initial begin
        $readmemh("axis_stimulus.mem", axis_stimulus);
        $readmemh("expected.mem", expected_result);

        cb.aresetn <= 1'b0;
        cb.s_axis_tdata <= 0;
        cb.s_axis_tkeep <= 0;
        cb.s_axis_tvalid <= 0;
        cb.s_axis_tlast <= 0;
        scheduler_ready <= 0;
        ##4;
        cb.aresetn <= 1'b1;
        ##1;
        
        for(int i = 0; i < 80; i = i + 1) begin    
            cb.s_axis_tdata    <= axis_stimulus[i][39:8];
            cb.s_axis_tkeep    <= normalize_keep(axis_stimulus[i][6:3], i);
            cb.s_axis_tvalid   <= axis_stimulus[i][2];
            cb.s_axis_tlast    <= axis_stimulus[i][1];
            scheduler_ready    <= axis_stimulus[i][0];

            if(axis_stimulus[i][2] == 1'b1) begin
                do begin
                    ##1;
                end while (cb.s_axis_tready !== 1'b1);
            end else begin
                ##1;
            end
        end

        cb.s_axis_tvalid <= 0;
        cb.s_axis_tlast <= 0;
        scheduler_ready <= 1;
        
        wait(j == 17);
        ##5;
        $finish();
    end

    initial begin
        forever begin
            @(cb);
            if (cb.sha_valid && scheduler_ready) begin
                if (j < 17) begin
                    error_count = error_check(cb.block, expected_result[j]);
                    errors(error_count);
                    j++;
                end
            end
        end
    end

    function automatic int error_check(input logic [511:0] actual, expected);
        int error = 0;
        if(actual !== expected) begin
            $display("Expected %h, got %h", expected, actual);
            error++;
        end
        error_check = error;
    endfunction

    function automatic void errors(input int error);
        if(error == 0) begin
            $display("Test Passed there are no errors");
        end else begin
            $display("Test failed, has %d errors", error);
        end
    endfunction

endmodule