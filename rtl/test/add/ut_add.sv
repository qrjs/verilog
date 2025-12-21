`timescale 1ns / 1ps


module ut_add;

    parameter P_CH = 1;
    parameter A_BIT = 4;

    logic                  clk;
    logic                  rst_n;
    logic [P_CH*A_BIT-1:0] in1_data;
    logic                  in1_valid;
    logic                  in1_ready;
    logic [P_CH*A_BIT-1:0] in2_data;
    logic                  in2_valid;
    logic                  in2_ready;
    logic [P_CH*A_BIT-1:0] out_data;
    logic                  out_valid;
    logic                  out_ready;
    logic [P_CH*A_BIT-1:0] in1_queue         [$];
    logic [P_CH*A_BIT-1:0] in2_queue         [$];
    int                    input_count;
    int                    output_count;
    int                    error_count;
    logic                  test_done;
    logic [     A_BIT-1:0] output_queue      [$];
    logic [     A_BIT-1:0] golden_queue      [$];
    int                    output_queue_size;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100MHz clock
    end

    add #(
        .P_CH (P_CH),
        .A_BIT(A_BIT)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .in1_data (in1_data),
        .in1_valid(in1_valid),
        .in1_ready(in1_ready),
        .in2_data (in2_data),
        .in2_valid(in2_valid),
        .in2_ready(in2_ready),
        .out_data (out_data),
        .out_valid(out_valid),
        .out_ready(out_ready)
    );

    // Input stimulus - drive in_valid randomly
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in1_valid <= 1'b0;
            in1_data  <= '0;
            in2_valid <= 1'b0;
            in2_data  <= '0;
        end else begin
            // Pop data when DUT accepts it
            if (in1_valid && in1_ready) begin
                in1_queue.pop_front();
            end
            if (in2_valid && in2_ready) begin
                in2_queue.pop_front();
            end

            // Random in_valid and drive data from queue
            if (in1_queue.size() > 0) begin
                in1_valid <= $urandom_range(0, 1);  // Random 0 or 1
                in1_data  <= in1_queue[0];
            end else begin
                in1_valid <= 1'b0;
                in1_data  <= '0;
            end

            if (in2_queue.size() > 0) begin
                in2_valid <= $urandom_range(0, 1);  // Random 0 or 1
                in2_data  <= in2_queue[0];
            end else begin
                in2_valid <= 1'b0;
                in2_data  <= '0;
            end
        end
    end

    // Random out_ready control
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_ready <= 1'b0;
        end else begin
            out_ready <= $urandom_range(0, 1);  // Random 0 or 1
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
            int          fd;
            int          code;
            logic [31:0] word_data;
            logic [31:0] word_data_swapped;

            // Read binary input file
            fd = $fopen("../../data/input.bin", "rb");
            if (fd == 0) begin
                $display("ERROR: Failed to open data/input.bin");
                $finish;
            end

            while ($fread(
                word_data, fd
            )) begin
                // Swap bytes for Little Endian to Big Endian conversion (if file is LE)
                // word_data_swapped = {<<8{word_data}};
                in1_queue.push_back(word_data[P_CH*A_BIT-1:0]);
            end
            $fclose(fd);
            $display("Loaded %0d entries into in1_queue", in1_queue.size());
        end

        // Load golden output data into the queue
        begin
            int          fd;
            int          code;
            logic [31:0] word_data;
            logic [31:0] word_data_swapped;

            // Read binary output file
            fd = $fopen("../../data/output.bin", "rb");
            if (fd == 0) begin
                $display("ERROR: Failed to open data/output.bin");
                $finish;
            end

            while ($fread(
                word_data, fd
            )) begin
                // word_data_swapped = {<<8{word_data}};
                golden_queue.push_back(word_data[A_BIT-1:0]);
            end
            $fclose(fd);
            $display("Loaded %0d entries into golden_queue", golden_queue.size());
        end

        // Load second input data into the queue (from final_q.bin)
        begin
            int          fd;
            logic [31:0] word_data;
            logic [31:0] word_data_swapped;

            // Read binary final_q file
            fd = $fopen("../../data/final_q.bin", "rb");
            if (fd == 0) begin
                $display("ERROR: Failed to open data/final_q.bin");
                $finish;
            end

            while ($fread(
                word_data, fd
            )) begin
                // word_data_swapped = {<<8{word_data}};
                in2_queue.push_back(word_data[P_CH*A_BIT-1:0]);
            end
            $fclose(fd);
            $display("Loaded %0d entries into in2_queue", in2_queue.size());
        end

        // Wait a bit
        repeat (5) @(posedge clk);

        // Wait for the queues to be empty
        wait (in1_queue.size() == 0 && in2_queue.size() == 0);
        @(posedge clk);
        $display("All inputs sent at time %0t", $time);

        // Wait some more cycles
        repeat (100) @(posedge clk);

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
            logic [A_BIT-1:0] expected, actual;

            expected = golden_queue[i];
            actual   = (i < output_queue.size()) ? output_queue[i] : 'x;

            if (actual !== expected) begin
                $display("ERROR at output[%0d]: expected=%0d (0x%0h), actual=%0d (0x%0h), diff=%0d", i, expected,
                         expected, actual, actual, actual - expected);
                error_count++;
            end else begin

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
            $display("*** TEST PASSED ***");
        end else begin
            $display("*** TEST FAILED ***");
        end
        $display("========================================\n");

        $finish;
    end

    // Collect outputs
    always @(posedge clk) begin
        if (rst_n && out_valid && out_ready) begin
            for (int p = 0; p < P_CH; p++) begin
                output_queue.push_back(out_data[p*A_BIT+:A_BIT]);
            end
        end
    end

    initial begin
        $fsdbDumpfile("ut_add.fsdb");
        $fsdbDumpvars(0, ut_add);
        $fsdbDumpMDA(0, ut_add);
        $fsdbDumpvars("+mda");
        $fsdbDumpvars("+all");
    end

endmodule
