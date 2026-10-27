#include "Vuddc_dec_core.h"
#include "verilated.h"
#include <array>
#include <fstream>
#include <iostream>
#include <random>
#include <vector>
struct Unit { int mode, error; std::array<uint32_t,32> in,out; };
std::array<uint32_t,32> words(std::string s) {
    std::array<uint32_t,32> w{};
    for(int i=0;i<32;i++) w[i]=std::stoul(s.substr(256-8*(i+1),8),nullptr,16);
    return w;
}
int main(int argc,char**argv) {
    Verilated::commandArgs(argc,argv);
    if(argc<2) return 2;
    bool continuous=false;
    int expected_first=-1, max_gaps=-1;
    for(int i=2;i<argc;i++) {
        std::string option=argv[i];
        if(option=="--continuous") continuous=true;
        else if(option.rfind("--expect-first=",0)==0) expected_first=std::stoi(option.substr(15));
        else if(option.rfind("--max-gaps=",0)==0) max_gaps=std::stoi(option.substr(11));
        else return 2;
    }
    std::ifstream f(argv[1]);
    std::vector<Unit> v; int mode,err; std::string a,b;
    while(f>>mode>>a>>b>>err) v.push_back({mode,err,words(a),words(b)});
    if(v.empty()) return 2;
    Vuddc_dec_core d;
    for(int i=0;i<10;i++) for(int j=0;j<4;j++) d.cfg_clear_pattern[i*4+j]=0x10203040+i+j;
    d.rst_n=0; d.s_valid=0; d.m_ready=0;
    for(int i=0;i<3;i++) { d.clk=0; d.eval(); d.clk=1; d.eval(); }
    d.rst_n=1;
    std::mt19937 rng(47019);
    int first_output=-1, output_gaps=0;
    size_t tx=0,rx=0; int tb=0,rb=0; bool pending=false,stalled=false;
    std::array<uint32_t,8> held{}; int held_sop=0,held_last=0,held_error=0;
    for(int cycle=0;cycle<100000 && rx<v.size();cycle++) {
        d.clk=0;
        if(!pending && tx<v.size() && (continuous || rng()%4!=0)) pending=true;
        d.s_valid=pending; d.m_ready=continuous || rng()%4!=0;
        int beats=1;
        if(tx<v.size()) {
            auto &u=v[tx]; beats=u.mode>=6?1:u.mode==0?4:u.mode==1?1:u.mode==5?3:2;
            d.s_sop=tb==0; d.s_last=tb==beats-1; d.s_cbmd=tb==0?u.mode:0; d.s_has_data=u.mode<6;
            for(int j=0;j<8;j++) d.s_data[j]=u.in[tb*8+j];
        }
        d.eval();
        if(stalled) {
            bool bad=!d.m_valid || d.m_sop!=held_sop || d.m_last!=held_last || d.m_error!=held_error;
            for(int j=0;j<8;j++) bad |= d.m_data[j]!=held[j];
            if(bad) { std::cerr<<"Output changed under backpressure\n"; return 1; }
        }
        stalled=d.m_valid&&!d.m_ready;
        if(stalled) { for(int j=0;j<8;j++) held[j]=d.m_data[j]; held_sop=d.m_sop; held_last=d.m_last; held_error=d.m_error; }
        if(first_output>=0 && !d.m_valid) output_gaps++;
        if(d.m_valid&&d.m_ready) {
            if(first_output<0) first_output=cycle;
            auto &u=v[rx]; bool bad=d.m_error!=u.error || d.m_sop!=(rb==0) || d.m_last!=(rb==3);
            for(int j=0;j<8;j++) bad |= d.m_data[j]!=u.out[rb*8+j];
            if(bad) { std::cerr<<"Mismatch unit="<<rx<<" mode="<<u.mode<<" beat="<<rb<<" error="<<int(d.m_error)<<" expected="<<u.error<<"\n"; return 1; }
            if(++rb==4) { rb=0;rx++; }
        }
        if(d.s_valid&&d.s_ready) { pending=false; if(++tb==beats) {tb=0;tx++;} }
        d.clk=1;d.eval();
    }
    d.final();
    if(rx!=v.size()) {std::cerr<<"Timeout tx="<<tx<<" rx="<<rx<<"\n";return 1;}
    if((expected_first>=0 && first_output!=expected_first) ||
       (max_gaps>=0 && output_gaps>max_gaps)) {
        std::cerr<<"Latency/continuity failure: first="<<first_output<<" gaps="<<output_gaps<<"\n";
        return 1;
    }
    std::cout<<"First output="<<first_output<<" output gaps="<<output_gaps<<"\n";
    std::cout<<"PASS "<<rx<<" units, "<<rx*4<<" output beats; data/error/framing/order/stability checked\n";
}
