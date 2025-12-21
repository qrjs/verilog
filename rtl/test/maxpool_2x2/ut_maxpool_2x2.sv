`timescale 1ns / 1ps
`include "../../data/maxpool_config.svh"

module ut_maxpool_2x2;
    logic                  clk;
    logic                  rst_n;
    logic [P_CH*A_BIT-1:0] in_data;
    logic                  in_valid;
    logic                  in_ready;
    logic [P_CH*A_BIT-1:0] out_data;
    logic                  out_valid;
    logic                  out_ready;

    logic [P_CH*A_BIT-1:0] input_queue           [$];
    int                    input_count;
    int                    output_count;
    int                    error_count;
    logic                  test_done;
    int                    cycle_count;
    int                    start_cycle;
    int                    first_output_cycle;
    int                    last_output_cycle;
    logic                  first_input_sent;
    logic                  first_output_received;
    logic [P_CH*A_BIT-1:0] output_queue          [$];
    logic [P_CH*A_BIT-1:0] golden_queue          [$];
    int                    output_queue_size;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    maxpool_2x2 #(
        .P_CH (P_CH),
        .N_CH (N_CH),
        .N_IH (N_IH),
        .N_IW (N_IW),
        .A_BIT(A_BIT)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_data(in_data),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .out_data(out_data),
        .out_valid(out_valid),
        .out_ready(out_ready)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_valid <= 1'b0;
            in_data  <= '0;
        end else begin
            if (in_valid && in_ready) begin
                input_queue.pop_front();
                if (!first_input_sent) begin
                    start_cycle      = cycle_count;
                    first_input_sent = 1;
                end
            end

            if (input_queue.size() > 0) begin
`ifdef PERF_TEST
                in_valid <= 1'b1;
`else
                in_valid <= $urandom_range(0, 1);
`endif
                in_data <= input_queue[0];
            end else begin
                in_valid <= 1'b0;
                in_data  <= '0;
            end
        end
    end

    // Random out_ready control
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_ready <= 1'b0;
        end else begin
`ifdef PERF_TEST
            out_ready <= 1'b1;
`else
            out_ready <= $urandom_range(0, 1);
`endif
        end
    end

    initial begin
        // Initialize
        rst_n                 = 0;
        input_count           = 0;
        test_done             = 0;
        first_input_sent      = 0;
        first_output_received = 0;

        repeat (10) @(posedge clk);
        rst_n = 1;
        $display("Reset released at time %0t", $time);

        begin
            int                     fd;
            string                  line;
            logic  [P_CH*A_BIT-1:0] data;
            fd = $fopen("../../data/maxpool_input.mem", "r");
            if (fd == 0) begin
                $display("ERROR: Failed to open maxpool_input.mem");
                $finish;
            end
            while (!$feof(
                fd
            )) begin
                if ($fscanf(fd, "%h\n", data) == 1) begin
                    input_queue.push_back(data);
                end
            end
            $fclose(fd);
            $display("Loaded %0d entries into input_queue", input_queue.size());
        end

        begin
            int                    fd;
            logic [P_CH*A_BIT-1:0] data;
            fd = $fopen("../../data/maxpool_output.mem", "r");
            if (fd == 0) begin
                $display("ERROR: Failed to open maxpool_output.mem");
                $finish;
            end
            while (!$feof(
                fd
            )) begin
                if ($fscanf(fd, "%h\n", data) == 1) begin
                    golden_queue.push_back(data);
                end
            end
            $fclose(fd);
            $display("Loaded %0d entries into golden_queue", golden_queue.size());
        end

        repeat (5) @(posedge clk);

        wait (input_queue.size() == 0);
        @(posedge clk);
        $display("All inputs sent at time %0t", $time);

        repeat (1000) @(posedge clk);

        $display("\n========================================");
        $display("Starting Output Verification");
        $display("========================================");

        error_count = 0;
        if (output_queue.size() != golden_queue.size()) begin
            $display("ERROR: Size mismatch! output_queue=%0d, golden_queue=%0d", output_queue.size(),
                     golden_queue.size());
        end

        for (int i = 0; i < golden_queue.size(); i++) begin
            logic [P_CH*A_BIT-1:0] expected, actual;

            expected = golden_queue[i];
            actual   = (i < output_queue.size()) ? output_queue[i] : 'x;

            if (actual !== expected) begin
                $display("ERROR at output[%0d]: expected=0x%0h, actual=0x%0h", i, expected, actual);
                error_count++;
            end else begin
                $display("PASS output[%0d]: value=0x%0h", i, actual);
            end
        end

        test_done = 1;

        // Wait some more cycles
        repeat (10) @(posedge clk);

        // Report results
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total outputs checked: %0d", golden_queue.size());
        $display("Errors found: %0d", error_count);

        if (error_count == 0) begin
            $display("*** TEST PASSED **!");
        end else begin
            $display("*** TEST FAILED **!");
        end
`ifdef PERF_TEST
        $display("Latency: %0d cycles", first_output_cycle - start_cycle);
        $display("Interval: %0d cycles", last_output_cycle - first_output_cycle);
`endif
        $display("========================================\n");
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && out_valid && out_ready) begin
            if (!first_output_received) begin
                first_output_cycle    = cycle_count;
                first_output_received = 1;
            end
            last_output_cycle = cycle_count;
            output_queue.push_back(out_data);
        end
    end

    initial begin
        $fsdbDumpfile("ut_maxpool_2x2.fsdb");
        $fsdbDumpvars(0, ut_maxpool_2x2);
        $fsdbDumpMDA(0, ut_maxpool_2x2);
        $fsdbDumpvars("+mda");
        $fsdbDumpvars("+all");
    end

endmodule
