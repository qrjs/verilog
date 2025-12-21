#include <iostream>
#include "add.h"
#include "utils.h"

// Define parameters if not available or to override
// unet_v1_params.h is included by add.h, so I_BIT and O_BIT are available.

template <unsigned DWIDTH>
void gen_ifm(data_stream<DWIDTH>& s_input, unsigned size) {
    for (unsigned i = 0; i < size; ++i) {
        s_input.write(i % (1 << DWIDTH));
    }
}

template<unsigned I_BIT, unsigned O_BIT>
void add_golden(data_stream<I_BIT>& in1, data_stream<O_BIT>& in2, data_stream<O_BIT>& out)
{
    unsigned VEC_LEN = in1.size();
    // We need to copy streams because reading consumes them, 
    // but we can just generate data twice like in tb_deconv.
    
    for (unsigned i = 0; i < VEC_LEN; ++i)
    {
        ap_uint<I_BIT> val1 = in1.read();
        ap_uint<O_BIT> val2_raw = in2.read();
        ap_int<O_BIT> val2 = val2_raw; // Reinterpret/Assign
        ap_uint<O_BIT> res = val1 + val2;
        out.write(res);
    }
}

int main()
{
    // Test parameters
    constexpr unsigned TEST_SIZE = 1024;
    
    // Create streams
    data_stream<I_BIT> s_in1("s_in1");
    data_stream<O_BIT> s_in2("s_in2");
    data_stream<O_BIT> s_out("s_out");

    data_stream<I_BIT> s_in1_golden("s_in1_golden");
    data_stream<O_BIT> s_in2_golden("s_in2_golden");
    data_stream<O_BIT> s_out_golden("s_out_golden");

    // Generate input data
    gen_ifm<I_BIT>(s_in1, TEST_SIZE);
    gen_ifm<I_BIT>(s_in1_golden, TEST_SIZE);
    
    gen_ifm<O_BIT>(s_in2, TEST_SIZE);
    gen_ifm<O_BIT>(s_in2_golden, TEST_SIZE);

    // Run DUT
    add(s_in1, s_in2, s_out);

    // Run Golden
    add_golden<I_BIT, O_BIT>(s_in1_golden, s_in2_golden, s_out_golden);

    // Check results
    // check_afm expects H, W, C. We can treat this as 1x1xTEST_SIZE or similar.
    // Let's use H=1, W=1, C=TEST_SIZE
    auto error_cnt = check_afm<O_BIT, 1, 1, TEST_SIZE>(s_out_golden, s_out, true);

    if(error_cnt > 0) {
        std::cout << "Test Failed! " << error_cnt << " errors" << std::endl;
        return 1;
    } else {
        std::cout << "Test Passed! " << std::endl;
        return 0;
    }
}
