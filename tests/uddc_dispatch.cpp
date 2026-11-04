#include "Vuddc_dec_split.h"
#include "verilated.h"
#include <array>
#include <iostream>
#include <vector>

// Test non-streaming response-driven dispatch and streaming prefix dispatch.
// A modeled parser marks completion when enough bytes are available.
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    for (int sectors : {1, 2, 3}) for (int size : {3, 40, 68}) {
        if (size > sectors * 32) continue;
        for (int stalled : {0, 1}) {
            Vuddc_dec_split d;
            d.pkg_streaming=0;d.pkg_response_valid=0;
            d.rst_n=0; d.s_valid=0; d.ctx_ready=1; d.pkg_ready=1;
            d.pkg_done=0; d.clear_ready=1; d.retire_valid=0;
            for(int i=0;i<3;i++) {d.clk=0;d.eval();d.clk=1;d.eval();}
            d.rst_n=1;
            int tx=0, completions=0, contexts=0;
            std::vector<int> cycles;
            std::array<uint32_t,24> held{};
            bool holding=false;
            int held_bytes=0, held_id=0, held_final=0;
            for(int cycle=0;cycle<40 && completions<2;cycle++) {
                d.clk=0;
                d.s_valid=tx<sectors; d.s_sop=tx==0;
                d.s_last=tx==sectors-1; d.s_has_data=1;
                d.s_cbmd=sectors==1?1:sectors==2?4:5;
                for(int j=0;j<8;j++) d.s_data[j]=0x100*tx+j;
                d.pkg_ready=!(stalled && cycle>=1 && cycle<=4);
                d.pkg_done=0;d.pkg_response_valid=0;d.eval();
                d.pkg_done=d.pkg_pkg_id || d.pkg_available_bytes>=size || d.pkg_final;
                d.pkg_response_valid=d.pkg_valid&&d.pkg_ready;
                d.eval();
                if(holding) {
                    if(!d.pkg_valid || d.pkg_available_bytes!=held_bytes ||
                       d.pkg_pkg_id!=held_id || d.pkg_final!=held_final) return 1;
                    for(int j=0;j<24;j++) if(d.pkg_region[j]!=held[j]) return 1;
                }
                holding=d.pkg_valid&&!d.pkg_ready;
                if(holding) {
                    held_bytes=d.pkg_available_bytes;held_id=d.pkg_pkg_id;held_final=d.pkg_final;
                    for(int j=0;j<24;j++) held[j]=d.pkg_region[j];
                }
                if(d.ctx_valid&&d.ctx_ready) contexts++;
                if(d.pkg_valid&&d.pkg_ready) {
                    if(!stalled) cycles.push_back(cycle);
                    if(d.pkg_pkg_id!=completions) return 1;
                    for(int j=0;j<int(d.pkg_available_bytes)/4;j++)
                        if(d.pkg_region[j]!=uint32_t(0x100*(j/8)+j%8)) return 1;
                    if(d.pkg_done) completions++;
                }
                if(d.s_valid&&d.s_ready) tx++;
                d.clk=1;d.eval();
            }
            if(completions!=2 || contexts!=1 || tx!=sectors) return 1;
            if(!stalled) {
                // Non-streaming mode: first prefix on cycle 1; later prefixes on successive
                // cycles, pkg1 immediately after pkg0 and final input supply.
                int needed=(size+31)/32;
                int pkg1_cycle=std::max(needed+1,sectors);
                if(cycles.front()!=1 || cycles.back()!=pkg1_cycle) return 1;
                if(sectors==3&&size==40&&cycles!=std::vector<int>({1,2,3})) return 1;
            }
        }
    }
    // No response is supplied in streaming mode: all prefixes must progress.
    for(int sectors : {1,2,3}) for(int stalled : {0,1}) {
        Vuddc_dec_split d;
        d.rst_n=0;d.s_valid=0;d.ctx_ready=1;d.pkg_ready=1;
        d.pkg_done=0;d.pkg_response_valid=0;d.pkg_streaming=1;
        d.clear_ready=1;d.retire_valid=0;
        for(int i=0;i<3;i++){d.clk=0;d.eval();d.clk=1;d.eval();}
        d.rst_n=1;
        int tx=0,requests=0,contexts=0;
        std::array<uint32_t,24> held{};
        bool holding=false;
        int held_bytes=0,held_package=0,held_final=0;
        for(int cycle=0;cycle<40;cycle++){
            d.clk=0;d.s_valid=tx<sectors;d.s_sop=tx==0;d.s_last=tx==sectors-1;
            d.s_has_data=1;d.s_cbmd=sectors==1?1:sectors==2?4:5;
            for(int j=0;j<8;j++)d.s_data[j]=0x100*tx+j;
            d.pkg_ready=!(stalled && cycle>=1 && cycle<=4);d.eval();
            if(holding){
                if(!d.pkg_valid || d.pkg_available_bytes!=held_bytes || d.pkg_pkg_id!=held_package || d.pkg_final!=held_final)return 1;
                for(int j=0;j<24;j++)if(d.pkg_region[j]!=held[j])return 1;
            }
            holding=d.pkg_valid&&!d.pkg_ready;
            if(holding){held_bytes=d.pkg_available_bytes;held_package=d.pkg_pkg_id;held_final=d.pkg_final;for(int j=0;j<24;j++)held[j]=d.pkg_region[j];}
            if(d.ctx_valid&&d.ctx_ready)contexts++;
            if(d.pkg_valid&&d.pkg_ready){
                int expected_package=requests==sectors;
                int expected_bytes=expected_package?sectors*32:(requests+1)*32;
                if(d.pkg_pkg_id!=expected_package || d.pkg_available_bytes!=expected_bytes)return 1;
                if(!stalled && cycle!=requests+1)return 1;
                if(d.pkg_final!=(expected_bytes==sectors*32))return 1;
                for(int j=0;j<24;j++) {
                    uint32_t expected=j<expected_bytes/4 ? 0x100*(j/8)+j%8 : 0;
                    if(d.pkg_region[j]!=expected)return 1;
                }
                requests++;
                if(d.pkg_pkg_id)break;
            }
            if(d.s_valid&&d.s_ready)tx++;
            d.clk=1;d.eval();
        }
        if(tx!=sectors || contexts!=1 || !d.pkg_pkg_id)return 1;
        if(requests!=sectors+1)return 1;
    }
    // Fill the allocation ring, then replace every retiring slot on its edge.
    {
        Vuddc_dec_split d;
        d.rst_n=0;d.s_valid=0;d.ctx_ready=0;d.pkg_ready=0;d.clear_ready=0;
        d.pkg_streaming=1;d.pkg_response_valid=0;d.pkg_done=0;d.retire_valid=0;
        auto tick=[&]{d.clk=0;d.eval();d.clk=1;d.eval();};
        tick();tick();d.rst_n=1;d.s_valid=1;d.s_sop=1;d.s_last=1;d.s_has_data=0;d.s_cbmd=6;
        int slots=0;
        for(;slots<32;slots++){d.clk=0;d.eval();if(!d.s_ready)break;d.clk=1;d.eval();}
        if(slots==0 || slots==32)return 1;
        for(int slot=0;slot<slots;slot++){
            d.clk=0;d.retire_valid=1;d.retire_unit_id=slot;d.eval();if(!d.s_ready)return 1;
            d.clk=1;d.eval();d.clk=0;d.retire_valid=0;d.eval();if(d.s_ready)return 1;
        }
    }
    std::cout<<"PASS streaming dispatch: consecutive prefixes without responses, stalled stability, final handoff and same-edge slot reuse\n";
    std::cout<<"PASS dispatcher: first-beat launch, consecutive snapshots, pkg1 handoff, 68B fallback, stalled snapshot stability\n";
}
