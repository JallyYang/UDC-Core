#include "Vuddc_dec_split.h"
#include "verilated.h"
#include <algorithm>
#include <array>
#include <iostream>
#include <vector>

// Keep an older generation live while the input ring buffers the next one.
// ctx_ready stays high to check the split's own ID ownership, independently
// of the identical live-ID guard in package_out.
bool check_input_lifetime(int slots, int mode, bool streaming) {
    Vuddc_dec_split d;
    d.clk=0; d.rst_n=0; d.s_valid=0; d.ctx_ready=0; d.pkg_ready=0;
    d.clear_ready=0; d.pkg_streaming=streaming; d.pkg_response_valid=0;
    d.pkg_done=0; d.retire_valid=0;
    for(int i=0;i<3;i++){d.clk=0;d.eval();d.clk=1;d.eval();}
    d.rst_n=1;
    const int beats=mode>=6?1:mode==0?4:mode==1?1:mode==5?3:2;
    const int total=3*slots;
    const bool compressed=mode>=1 && mode<=5;
    int tx=0, beat=0, contexts=0, finals=0, clears=0, cycle=0;
    std::vector<bool> active(slots, false);
    std::vector<int> serial(slots, -1), final_mask(total, 0);
    auto word=[](int unit, int index){return uint32_t(0x20000000u+unit*0x100u+index);};
    auto fail=[&](const char* message){
        std::cerr<<"Lifetime failure: mode="<<mode<<" streaming="<<streaming
                 <<" cycle="<<cycle<<" tx="<<tx<<" contexts="<<contexts
                 <<": "<<message<<"\n";
        return false;
    };
    auto step=[&](bool context_ready, bool retire, int retire_id, bool input_blocked){
        d.clk=0; d.ctx_ready=context_ready; d.clear_ready=1;
        d.pkg_ready=cycle%5!=2; d.retire_valid=retire; d.retire_unit_id=retire_id;
        d.s_valid=tx<total; d.s_sop=beat==0; d.s_last=beat==beats-1;
        d.s_cbmd=beat==0?mode:0; d.s_has_data=mode<6;
        for(int j=0;j<8;j++) d.s_data[j]=word(tx,beat*8+j);
        d.pkg_response_valid=0; d.pkg_done=0; d.eval();
        d.pkg_response_valid=!streaming && d.pkg_valid && d.pkg_ready;
        d.pkg_done=d.pkg_final; d.eval();
        if(input_blocked && d.s_ready) return fail("retirement released a buffered input");
        if(d.ctx_valid && active[d.ctx_unit_id]) return fail("live ID offered twice");
        if(d.ctx_valid && d.ctx_ready){
            if(contexts>=total || d.ctx_unit_id!=contexts%slots || d.ctx_cbmd!=mode)
                return fail("context order or mode changed");
            if(mode==0) for(int j=0;j<32;j++)
                if(d.ctx_raw[j]!=word(contexts,j)) return fail("buffered raw unit overwritten");
            active[d.ctx_unit_id]=true; serial[d.ctx_unit_id]=contexts++;
        }
        if(d.pkg_valid && d.pkg_ready){
            int id=d.pkg_unit_id, unit=serial[id], package=d.pkg_pkg_id;
            if(!compressed || !active[id] || unit<0 || d.pkg_cbmd!=mode)
                return fail("request without its context");
            if(d.pkg_available_bytes==0 || d.pkg_available_bytes>beats*32 ||
               d.pkg_available_bytes%32 || (package && !d.pkg_final) ||
               (d.pkg_final && d.pkg_available_bytes!=beats*32))
                return fail("invalid prefix size or final marker");
            for(int j=0;j<24;j++){
                uint32_t expected=j<int(d.pkg_available_bytes)/4?word(unit,j):0;
                if(d.pkg_region[j]!=expected) return fail("snapshot changed after slot reuse");
            }
            if(d.pkg_final){
                if(final_mask[unit]&(1<<package)) return fail("duplicate final request");
                final_mask[unit]|=1<<package; finals++;
            }
        }
        if(d.clear_valid && d.clear_ready){
            int id=d.clear_unit_id;
            if(mode<6 || !active[id] || serial[id]!=clears || d.clear_index!=mode-6)
                return fail("clear request order or index changed");
            clears++;
        }
        if(retire){
            if(!active[retire_id]) return fail("test retired an inactive ID");
            active[retire_id]=false;
        }
        if(d.s_valid && d.s_ready && ++beat==beats){beat=0;tx++;}
        d.clk=1; d.eval(); cycle++;
        return true;
    };
    for(int generation=0;generation<3;generation++){
        int target=(generation+1)*slots;
        int input_target=std::min(total,(generation+2)*slots);
        bool completed=false;
        for(int wait=0;wait<5000;wait++){
            if(!step(true,false,0,false)) return false;
            if(contexts>target) return fail("next generation dispatched before retirement");
            if(tx==input_target && beat==0 && contexts==target &&
               (!compressed || finals==2*target) && (mode<6 || clears==target)){
                completed=true; break;
            }
        }
        if(!completed) return fail("dispatch or early prefetch timed out");
        if(generation<2){
            for(int wait=0;wait<3;wait++) if(!step(true,false,0,true)) return false;
            // All input slots contain the next generation. The old retirement
            // must neither clear them nor enable a same-edge overwrite.
            for(int id=0;id<slots;id++) if(!step(false,true,id,true)) return false;
            for(int wait=0;wait<3;wait++) if(!step(false,false,0,true)) return false;
        }
    }
    for(int wait=0;wait<8;wait++) if(!step(true,false,0,false)) return false;
    return contexts==total && tx==total;
}

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
    // Discover the configured input capacity without dispatching any unit.
    int slots=0;
    {
        Vuddc_dec_split d;
        d.rst_n=0;d.s_valid=0;d.ctx_ready=0;d.pkg_ready=0;d.clear_ready=0;
        d.pkg_streaming=1;d.pkg_response_valid=0;d.pkg_done=0;d.retire_valid=0;
        auto tick=[&]{d.clk=0;d.eval();d.clk=1;d.eval();};
        tick();tick();d.rst_n=1;d.s_valid=1;d.s_sop=1;d.s_last=1;d.s_has_data=0;d.s_cbmd=6;
        for(;slots<32;slots++){d.clk=0;d.eval();if(!d.s_ready)break;d.clk=1;d.eval();}
        if(slots==0 || slots==32)return 1;
    }
    for(int mode : {0,1,4,5,6,15}) for(bool streaming : {false,true})
        if(!check_input_lifetime(slots,mode,streaming)) return 1;
    std::cout<<"PASS independent lifetimes: early input reuse, three generations, live-ID blocking, retirement isolation, raw/snapshot/clear preservation\n";
    std::cout<<"PASS streaming dispatch: consecutive prefixes without responses, stalled stability and final handoff\n";
    std::cout<<"PASS dispatcher: first-beat launch, consecutive snapshots, pkg1 handoff, 68B fallback, stalled snapshot stability\n";
}
