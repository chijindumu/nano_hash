module digest_buffer_tb;
    timeunit 1ns;
    timeprecision 1ps;

    logic aresetn;
    logic [255:0] digest;
    logic digest_valid;
    logic m_axis_tready;

    logic [31:0] m_axis_tdata;
    logic m_axis_tvalid;
    logic m_axis_tlast;

    logic aclk = 1'b1;

    logic [31:0] expected_d0 [0:7];
    logic [31:0] expected_d1 [0:7];
    logic [31:0] expected_d2 [0:7];
    logic [31:0] expected_d3 [0:7];

    int error_count = 0;

    digest_buffer dut(.*);

    always #5 aclk = ~aclk;

    default clocking cb @(posedge aclk);
        default input #1step output #1;
        input m_axis_tdata, m_axis_tlast, m_axis_tvalid;
        output aresetn, digest, digest_valid, m_axis_tready;
    endclocking

    initial begin
        $readmemh("digest0.mem", expected_d0);
        $readmemh("digest1.mem", expected_d1);
        $readmemh("digest2.mem", expected_d2);
        $readmemh("digest3.mem", expected_d3);

        cb.aresetn <= 0;
        cb.digest <= 0;
        cb.digest_valid <= 0;
        cb.m_axis_tready <= 0;
        ##4         // wait for global reset
        cb.aresetn <= 1;
        ##2;

        run_digest(256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad, expected_d0);
        run_digest(256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855, expected_d1);
        run_digest(256'h71c480df93d6ae2f1efad1447c66c9525e316218cf51fc8d9ed832f2daf18b73, expected_d2);
        run_digest(256'h248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1, expected_d3);

        if(error_count == 0)
            $display("The 32 tests passed!!");
        else
            $display("%d tests failed!", error_count);

        ##5;
        $finish();
    end

    task automatic run_digest(input logic [255:0] r_digest, input logic [31:0] r_expected [0:7]);
        digest = r_digest;
        digest_valid = 1;
        @(cb);
        digest_valid = 0;
        for(int i = 0; i < 8; i++) begin
            m_axis_tready = 1;
           if(m_axis_tdata == r_expected[i]) 
                $display("Test Passed!");
            else begin
                error_count++;
                $display("Test Failed, expected %h, got %h", r_expected[i], m_axis_tdata);
            end
            @(cb);
            m_axis_tready = 0;
            repeat(2) @(cb);
        end
        @(cb);
    endtask

    
endmodule