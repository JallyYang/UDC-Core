#include "Vde_rs_reg_test.h"
#include "verilated.h"
#include <array>
#include <deque>
#include <iostream>
#include <random>
#include <stdexcept>

using Payload = std::array<uint32_t, 32>;
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vde_rs_reg_test d;
    std::mt19937 rng(0xdec0de);
    std::array<std::deque<Payload>, 8> queues;
    std::array<bool, 8> pending{};
    const int widths[] = {1, 32, 256, 1024};
    unsigned writes=0, reads=0, simultaneous=0, full_pops=0;
    auto tick = [&] {d.clk=1; d.eval(); d.clk=0; d.eval();};
    auto reset = [&] {
        d.input_valid=0; d.rst_n=0; d.clk=0; d.eval(); tick();
        if (d.output_valid || d.input_ready!=255) throw std::runtime_error("reset control");
        for (int lane=0;lane<4;lane++)
            for(int w=0;w<32;w++)
                if(d.output_payload[lane*32+w]) throw std::runtime_error("NORST=0 data reset");
        for(auto& q:queues) q.clear();
        pending.fill(false); d.rst_n=1; d.eval();
    };
    try {
        reset();
        for (int cycle=0;cycle<40000;cycle++) {
            if(cycle && cycle%997==0) reset();
            d.input_valid=0; d.output_ready=0;
            for(int lane=0;lane<8;lane++) {
                int width=widths[lane%4];
                // Directed fill, full+pop, then uninterrupted transfers precede random stalls.
                if(!pending[lane] && (cycle<80 || rng()%4)) {
                    pending[lane]=true;
                    for(int w=0;w<32;w++)
                        d.input_payload[lane*32+w]=w*32<width ? rng() : 0;
                    if(width==1) d.input_payload[lane*32]&=1;
                }
                if(pending[lane]) d.input_valid|=1u<<lane;
                bool ready=cycle<4 ? false : cycle<80 ? true :
                           cycle%97<20 ? false : (rng()%4!=0);
                if(ready) d.output_ready|=1u<<lane;
            }
            d.eval();
            auto original_ready=d.input_ready;
            d.output_ready^=255; d.eval();
            if(d.input_ready!=original_ready) throw std::runtime_error("combinational ready chain");
            d.output_ready^=255; d.eval();
            for(int lane=0;lane<8;lane++) {
                auto& q=queues[lane];
                bool in_ready=(d.input_ready>>lane)&1;
                bool out_valid=(d.output_valid>>lane)&1;
                if(in_ready!=(q.size()<2) || out_valid!=!q.empty())
                    throw std::runtime_error("two-entry occupancy/valid mismatch");
                if(out_valid)
                    for(int w=0;w<32;w++)
                        if(d.output_payload[lane*32+w]!=q.front()[w])
                            throw std::runtime_error("payload order/stalled stability mismatch");
                bool push=in_ready && ((d.input_valid>>lane)&1);
                bool pop=out_valid && ((d.output_ready>>lane)&1);
                if(q.size()==2 && pop) full_pops++;
                if(push && pop) simultaneous++;
                if(pop) {q.pop_front(); reads++;}
                if(push) {
                    Payload p;
                    for(int w=0;w<32;w++) p[w]=d.input_payload[lane*32+w];
                    q.push_back(p); pending[lane]=false; writes++;
                }
            }
            tick();
        }
        d.input_valid=0; d.output_ready=255;
        for(int cycle=0;cycle<3;cycle++) {
            d.eval();
            for(int lane=0;lane<8;lane++) {
                if(bool((d.output_valid>>lane)&1)!=!queues[lane].empty())
                    throw std::runtime_error("drain valid mismatch");
                if(!queues[lane].empty()) {
                    for(int w=0;w<32;w++)
                        if(d.output_payload[lane*32+w]!=queues[lane].front()[w])
                            throw std::runtime_error("drain data mismatch");
                    queues[lane].pop_front(); reads++;
                }
            }
            tick();
        }
        if(!simultaneous || !full_pops) throw std::runtime_error("missing directed coverage");
        std::cout<<"PASS de_rs_reg: NORST=0/1, widths=1/32/256/1024, 40000 cycles, "
                 <<writes<<" writes, "<<reads<<" reads, "<<simultaneous
                 <<" simultaneous transfers, "<<full_pops<<" full+pop edges; ready isolation and reset\n";
    } catch(const std::exception& e) {std::cerr<<e.what()<<'\n';return 1;}
}
