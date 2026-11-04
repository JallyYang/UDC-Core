#include "Vlegacy_compare.h"
#include "verilated.h"
#include <array>
#include <vector>
#include <random>
#include <stdexcept>
#include <iostream>

struct Input { unsigned id, pkg, fmt; std::array<uint32_t,16> raw; };
struct Result {
    unsigned id, pkg, fmt, size, error;
    std::array<uint32_t,17> bits;
    bool operator==(const Result&) const = default;
};
int main(int argc,char** argv) {
    Verilated::commandArgs(argc,argv);
    Vlegacy_compare d;
    std::mt19937 random(0x6432);
    std::vector<Input> inputs;
    for(unsigned i=0;i<1024;i++) {
        Input p{i%16,(i/16)%2,1+i%14,{}};
        for(unsigned w=0;w<16;w++) p.raw[w]=i%4==0?0:i%4==1?w:i%4==2?0x12345678:random();
        inputs.push_back(p);
    }
    auto tick=[&] {d.clk=1;d.eval();d.clk=0;d.eval();};
    auto drive=[&](bool reference,const Input& p) {
        if(reference) {
            d.r_s_unit_id=p.id;d.r_s_pkg_id=p.pkg;d.r_s_fmt=p.fmt;
            for(int w=0;w<16;w++) d.r_s_raw[w]=p.raw[w];
        } else {
            d.n_s_unit_id=p.id;d.n_s_pkg_id=p.pkg;d.n_s_fmt=p.fmt;
            for(int w=0;w<16;w++) d.n_s_raw[w]=p.raw[w];
        }
    };
    auto result=[&](bool reference) {
        Result p;
        if(reference) {
            p.id=d.r_m_unit_id;p.pkg=d.r_m_pkg_id;p.fmt=d.r_m_fmt;
            p.size=d.r_m_size_bytes;p.error=d.r_m_error;
            for(int w=0;w<17;w++) p.bits[w]=d.r_m_bits[w];
        } else {
            p.id=d.n_m_unit_id;p.pkg=d.n_m_pkg_id;p.fmt=d.n_m_fmt;
            p.size=d.n_m_size_bytes;p.error=d.n_m_error;
            for(int w=0;w<17;w++) p.bits[w]=d.n_m_bits[w];
        }
        return p;
    };
    try {
        d.rst_n=0;d.clk=0;d.n_s_valid=0;d.r_s_valid=0;d.n_m_ready=0;d.r_m_ready=0;
        tick();tick();d.rst_n=1;
        std::array<unsigned,2> sent{};
        std::array<bool,2> pending{},stalled{};
        std::array<Result,2> held{};
        std::array<std::vector<Result>,2> outputs;
        unsigned compared=0;
        for(int cycle=0;cycle<200000;cycle++) {
            for(int path=0;path<2;path++) {
                if(!pending[path] && sent[path]<inputs.size() && random()%4) pending[path]=true;
                if(sent[path]<inputs.size()) drive(path,inputs[sent[path]]);
            }
            d.n_s_valid=pending[0];d.r_s_valid=pending[1];
            d.n_m_ready=cycle%83<17?0:random()%4!=0;
            d.r_m_ready=cycle%61<11?0:random()%3!=0;
            d.eval();
            for(int path=0;path<2;path++) {
                bool valid=path?d.r_m_valid:d.n_m_valid;
                bool ready=path?d.r_m_ready:d.n_m_ready;
                auto p=result(path);
                if(stalled[path] && (!valid || !(p==held[path])))
                    throw std::runtime_error("stalled result changed");
                stalled[path]=valid&&!ready;held[path]=p;
                if(valid&&ready) {
                    unsigned index=outputs[path].size();
                    if(index>=inputs.size() || p.id!=inputs[index].id || p.pkg!=inputs[index].pkg || p.fmt!=inputs[index].fmt)
                        throw std::runtime_error("tag/order mismatch");
                    outputs[path].push_back(p);
                }
                if(pending[path] && (path?d.r_s_ready:d.n_s_ready)) {sent[path]++;pending[path]=false;}
            }
            while(compared<outputs[0].size() && compared<outputs[1].size()) {
                if(!(outputs[0][compared]==outputs[1][compared]))
                    throw std::runtime_error("legacy package mismatch at "+std::to_string(compared));
                compared++;
            }
            tick();
            if(compared==inputs.size()) {
                d.n_s_valid=0;d.r_s_valid=0;d.n_m_ready=1;d.r_m_ready=1;
                for(int i=0;i<20;i++) {d.eval();if(d.n_m_valid||d.r_m_valid) throw std::runtime_error("duplicate result");tick();}
                std::cout<<"PASS standalone udc_dic_enc: 1024 packages, 14 formats, original/color selection, tags, stalls; bit-exact against eb71130\n";
                return 0;
            }
        }
        throw std::runtime_error("timeout");
    } catch(const std::exception& e) {std::cerr<<e.what()<<'\n';return 1;}
}
