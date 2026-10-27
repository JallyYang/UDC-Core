#include "Vuddc_package_out.h"
#include "verilated.h"
#include <iostream>

// The final package can make the first output beat valid before cache writeback.
// Exercise both arrival orders and the transition from forwarding to storage.
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    for (int last_package : {0, 1}) for (int error_case=0; error_case<4; ++error_case)
    for (int stall_cycles : {0, 3}) {
        Vuddc_package_out d;
        auto tick = [&]() { d.clk=1; d.eval(); d.clk=0; d.eval(); };
        d.clk=0; d.rst_n=0; d.ctx_valid=0; d.pkg_valid=0;
        d.clear_valid=0; d.m_ready=1; d.eval(); tick(); tick();
        d.rst_n=1; d.ctx_valid=1; d.ctx_unit_id=0; d.ctx_cbmd=2;
        for (int i=0;i<32;i++) d.ctx_raw[i]=0;
        d.eval();
        if (!d.ctx_ready) return 1;
        tick(); d.ctx_valid=0;
        auto present = [&](int package) {
            d.pkg_valid=1; d.pkg_unit_id=0; d.pkg_pkg_id=package;
            d.pkg_fmt=(error_case==2 && package==last_package)?2:1;
            d.pkg_size_bytes=error_case==3?40:20;
            d.pkg_error=error_case==1 && package==last_package;
            for (int i=0;i<16;i++) d.pkg_raw[i]=0x10000000+package*16+i;
            d.eval();
        };
        present(1-last_package);
        if (!d.pkg_ready || d.m_valid) return 1;
        tick(); d.pkg_valid=0; d.eval();
        if (d.m_valid) return 1;
        int output_beat=0;
        for (int cycle=0;cycle<10 && output_beat<4;cycle++) {
            d.m_ready=cycle>=stall_cycles;
            if (cycle==0) present(last_package);
            else { d.pkg_valid=0; d.eval(); }
            if (!d.m_valid || d.m_error!=(error_case!=0) ||
                d.m_sop!=(output_beat==0) || d.m_last!=(output_beat==3)) return 1;
            for (int i=0;i<8;i++) {
                unsigned expected=error_case?0:0x10000000+output_beat*8+i;
                if (d.m_data[i]!=expected) return 1;
            }
            if (d.retire_valid!=(d.m_ready && output_beat==3)) return 1;
            if (d.m_ready) output_beat++;
            tick();
        }
        if (output_beat!=4 || d.m_valid) return 1;
    }
    std::cout<<"PASS output forwarding: both package orders, stalls, errors, format/size checks, retirement\n";
}
