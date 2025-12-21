`timescale 1ns / 1ps

// Include auto-generated configuration
`include "../../data/deconv_config.svh"

module ut_deconv;

    // Clock and reset
    logic                          clk;
    logic                          rst_n;

    // DUT signals
    logic        [P_ICH*A_BIT-1:0] in_data;
    logic                          in_valid;
    logic                          in_ready;
    logic        [P_OCH*B_BIT-1:0] out_data;
    logic                          out_valid;
    logic                          out_ready;

    logic        [P_ICH*A_BIT-1:0] input_queue       [$];

    // Test control
    int                            input_count;
    int                            output_count;
    int                            error_count;
    logic                          test_done;

    // Queues for output comparison
    logic signed [      B_BIT-1:0] output_queue      [$];  // Actual outputs from DUT
    logic signed [      B_BIT-1:0] golden_queue      [$];  // Expected outputs from file
    int                            output_queue_size;

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100MHz clock
    end

    // DUT instantiation
    deconv #(
        .P_ICH(P_ICH),
        .P_OCH(P_OCH),
        .N_ICH(N_ICH),
        .N_OCH(N_OCH),
        .N_IH(IN_H),
        .N_IW(IN_W),
        .K(K),
        .P(PADDING),
        .S(STRIDE),
        .O_P(OUTPUT_PADDING),
        .Z_NUM(Z_NUM),
        .A_BIT(A_BIT),
        .W_BIT(W_BIT),
        .B_BIT(B_BIT),
        .W_FILE("../../data/deconv_weight.mem")
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

    // Input stimulus - drive in_valid randomly
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_valid <= 1'b0;
            in_data  <= '0;
        end else begin
            // Pop data when DUT accepts it
            if (in_valid && in_ready) begin
                input_queue.pop_front();
            end

            // Random in_valid and drive data from queue
            if (input_queue.size() > 0) begin
                in_valid <= $urandom_range(0, 1);  // Random 0 or 1
                in_data  <= input_queue[0];
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
            out_ready <= $urandom_range(0, 1);
        end
    end

    initial begin
        // Initialize
        rst_n       = 0;
        input_count = 0;
        test_done   = 0;

        // Reset
        repeat (10) @(posedge clk);
        rst_n = 1;
        $display("Reset released at time %0t", $time);

        // Load input data into the queue
        begin
            int                      fd;
            string                   line;
            logic  [P_ICH*A_BIT-1:0] data;
            fd = $fopen("../../data/deconv_input.mem", "r");
            if (fd == 0) begin
                $display("ERROR: Failed to open deconv_input.mem");
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

        // Load golden output data into the queue
        begin
            int                      fd;
            logic signed [B_BIT-1:0] data;
            fd = $fopen("../../data/deconv_output.mem", "r");
            if (fd == 0) begin
                $display("ERROR: Failed to open deconv_output.mem");
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

        // Wait a bit
        repeat (5) @(posedge clk);

        // Wait for the queue to be empty, meaning all inputs have been sent and processed
        wait (input_queue.size() == 0);
        @(posedge clk);
        $display("All inputs sent at time %0t (count=%0d)", $time, input_count);

        // Wait some more cycles
        repeat (1000000) @(posedge clk);

        // Now compare all collected outputs with golden data
        $display("\n========================================");
        $display("Starting Output Verification");
        $display("========================================");

        error_count = 0;
        if (output_queue.size() != golden_queue.size()) begin
            $display("ERROR: Size mismatch! output_queue=%0d, golden_queue=%0d", output_queue.size(),
                     golden_queue.size());
        end

        for (int i = 0; i < golden_queue.size(); i++) begin
            logic signed [B_BIT-1:0] expected, actual;
            expected = golden_queue[i];
            actual   = (i < output_queue.size()) ? output_queue[i] : 'x;
            if (actual !== expected) begin
                $display("ERROR at output[%0d]: expected=%0d (0x%0h), actual=%0d (0x%0h), diff=%0d", i, expected,
                         expected, actual, actual, actual - expected);
                error_count++;
            end else begin
                $display("PASS output[%0d]: value=%0d (0x%0h)", i, actual, actual);
            end
        end

        test_done = 1;

        // Wait some more cycles
        repeat (100000) @(posedge clk);

        // Report results
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total outputs checked: %0d", golden_queue.size());
        $display("Errors found: %0d", error_count);

        if (error_count == 0) begin
            $display("*** TEST PASSED ***");
        end else begin
            $display("*** TEST FAILED ***");
        end
        $display("========================================\n");

        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && out_valid && out_ready) begin
            for (int p = 0; p < P_OCH; p++) begin
                logic signed [B_BIT-1:0] received_data;
                received_data = out_data[p*B_BIT+:B_BIT];
                output_queue.push_back(received_data);
            end
        end
    end

    // Waveform dump for Verdi
    initial begin
        $fsdbDumpfile("ut_deconv.fsdb");
        $fsdbDumpvars(0, ut_deconv);

        // Dump all arrays including multi-dimensional arrays
        $fsdbDumpMDA(0, ut_deconv);

        // Enable dumping of memories
        $fsdbDumpvars("+mda");
        $fsdbDumpvars("+all");
    end

endmodule
