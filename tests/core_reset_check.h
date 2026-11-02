#pragma once
#include "verilated.h"
#include <iostream>

// Common stream pins; mode-specific pins are supplied by callbacks below.
struct ResetStream {
    CData &input_valid, &input_ready, &input_sop, &input_last;
    VlWide<8> &input_data;
    CData &output_valid, &output_ready, &output_sop, &output_last;
    VlWide<8> &output_data;
};

template<class Model, class SetMode, class CheckOutput>
bool check_reset_recovery(Model &d, ResetStream p, int dirty_beats,
                          SetMode set_mode, CheckOutput check_output) {
    auto tick = [&] { d.clk=0; d.eval(); d.clk=1; d.eval(); };
    auto reset = [&] {
        // Assert between clock edges. There are no valid transfers in reset.
        d.clk=0; p.input_valid=0; p.output_ready=0; d.eval();
        d.rst_n=0; d.eval();
        tick(); tick();
        d.clk=0; d.rst_n=1; d.eval();
    };
    auto word = [](int beat, int lane) {
        return uint32_t(0xa5910000u + beat*0x100u + lane);
    };
    int cases=0;
    for (int prefix=1; prefix<=dirty_beats; ++prefix) {
        for (int delay : {0, 3, 12}) {
            reset();
            set_mode(false);
            int sent=0;
            // Start a DIC transaction, then interrupt at input/pipeline/output
            // stages. The output is stalled so a completed unit stays live.
            for (int cycle=0; cycle<100 && sent<prefix; ++cycle) {
                d.clk=0; p.input_valid=1;
                p.input_sop=sent==0; p.input_last=sent==dirty_beats-1;
                for (int j=0;j<8;++j) p.input_data[j]=0;
                d.eval(); bool accepted=p.input_ready;
                d.clk=1; d.eval();
                if (accepted) ++sent;
            }
            if (sent!=prefix) { std::cerr<<"Reset setup input timeout\n"; return false; }
            p.input_valid=0;
            for (int cycle=0;cycle<delay;++cycle) tick();
            reset();
            p.output_ready=1;
            for (int cycle=0;cycle<3;++cycle) {
                tick();
                if (p.output_valid) { std::cerr<<"Stale output after reset\n"; return false; }
            }
            set_mode(true);
            int received=0;
            sent=0;
            for (int cycle=0;cycle<100 && received<4;++cycle) {
                d.clk=0; p.input_valid=sent<4;
                p.input_sop=sent==0; p.input_last=sent==3;
                for (int j=0;j<8;++j) p.input_data[j]=word(sent,j);
                d.eval();
                if (p.output_valid) {
                    bool bad=p.output_sop!=(received==0) || p.output_last!=(received==3) || !check_output();
                    for (int j=0;j<8;++j) bad |= p.output_data[j]!=word(received,j);
                    if (bad) { std::cerr<<"Reset recovery data/framing mismatch\n"; return false; }
                    ++received;
                }
                if (p.input_valid && p.input_ready) ++sent;
                d.clk=1; d.eval();
            }
            if (sent!=4 || received!=4) { std::cerr<<"Reset recovery timeout\n"; return false; }
            p.input_valid=0;
            for (int cycle=0;cycle<16;++cycle) {
                tick();
                if (p.output_valid) { std::cerr<<"Extra output after reset recovery\n"; return false; }
            }
            ++cases;
        }
    }
    std::cout<<"PASS reset recovery: "<<cases<<" interrupted-input/pipeline/stalled-output cases\n";
    return true;
}
