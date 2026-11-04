#include "Vparser_compare.h"
#include "verilated.h"
#include <array>
#include <deque>
#include <fstream>
#include <iostream>
#include <random>
#include <string>
#include <vector>
struct Request {
    std::array<uint32_t,24> data{};
    int mode, package, available, final, id;
};
struct Result {
    std::array<uint32_t,4> anchors{};
    std::array<uint32_t,16> deltas{};
    int format, decor, size, error, id, package;
    bool operator==(const Result&) const = default;
};
int main(int argc,char **argv) {
    Verilated::commandArgs(argc,argv);
    if(argc!=2) return 2;
    std::ifstream input(argv[1]);
    std::vector<Request> requests;
    int mode,error,unit_id=0;
    std::string bits,raw;
    while(input>>mode>>bits>>raw>>error) {
        if(mode<1 || mode>5) continue;
        int occupied=mode==1?32:mode==5?96:64;
        for(int package=0;package<2;package++) for(int available=32;available<=occupied;available+=32) {
            Request r{};
            r.mode=mode;r.package=package;r.available=available;r.final=available==occupied;r.id=unit_id%16;
            for(int j=0;j<24;j++) r.data[j]=std::stoul(bits.substr(256-8*(j+1),8),nullptr,16);
            requests.push_back(r);
        }
        unit_id++;
    }
    for(int m : {0,6,15}) { Request r{};r.mode=m;r.available=32;r.final=1;r.id=3;requests.push_back(r); }
    for(int f : {0,15}) { Request r{};r.mode=1;r.available=32;r.final=1;r.data[0]=f<<2;r.id=7;requests.push_back(r); }
    Vparser_compare d;
    std::mt19937 random(57019);
    auto tick=[&]{d.clk=0;d.eval();d.clk=1;d.eval();};
    auto drive=[&](const Request&r){
        d.s_unit_id=r.id;d.s_pkg_id=r.package;d.s_cbmd=r.mode;d.s_available_bytes=r.available;d.s_final=r.final;
        for(int j=0;j<24;j++)d.s_region[j]=r.data[j];
    };
    d.rst_n=0;d.s_valid=0;d.reference_valid=0;d.m_ready=0;tick();tick();d.rst_n=1;
    std::vector<bool> expected_done;
    std::vector<Result> expected_result;
    for(auto&r:requests){
        d.clk=0;drive(r);d.reference_valid=1;d.eval();expected_done.push_back(d.reference_done);
        d.clk=1;d.eval();Result value{};
        value.format=d.reference_fmt;value.decor=d.reference_decor;value.size=d.reference_size;value.error=d.reference_error;value.id=r.id;value.package=r.package;
        for(int j=0;j<4;j++)value.anchors[j]=d.reference_anchors[j];
        for(int j=0;j<16;j++)value.deltas[j]=d.reference_deltas[j];
        expected_result.push_back(value);
    }
    d.reference_valid=0;
    std::array<std::deque<size_t>,8> responses;
    std::array<std::deque<size_t>,8> outputs;
    std::array<Result,8> held{};
    std::array<bool,8> stalled{};
    std::array<int,8> response_count{};
    std::array<std::array<bool,32>,8> result_sent{};
    std::array<int,8> suppressed{};
    auto read_result=[&](int i){
        Result value{};value.format=(d.m_fmt>>(i*4))&15;value.decor=(d.m_decor>>i)&1;
        value.size=(d.m_size>>(i*7))&127;value.error=(d.m_error>>i)&1;value.id=(d.m_unit_id>>(i*4))&15;value.package=(d.m_pkg_id>>i)&1;
        for(int j=0;j<4;j++)value.anchors[j]=d.m_anchors[i*4+j];
        for(int j=0;j<16;j++)value.deltas[j]=d.m_deltas[i*16+j];
        return value;
    };
    size_t next=0;
    unsigned accepted=0;
    bool pending=false;
    int idle=0;
    for(int cycle=0;cycle<200000;cycle++){
        d.clk=0;
        if(!pending && next<requests.size() && random()%4){pending=true;accepted=0;}
        if(pending)drive(requests[next]);
        d.s_valid=pending?255u^accepted:0;d.m_ready=random()&255;d.eval();
        for(int i=0;i<8;i++){
            if((d.s_valid&d.s_ready)&(1u<<i)){responses[i].push_back(next);accepted|=1u<<i;}
            if(d.response_valid&(1u<<i)){
                if(responses[i].empty()){std::cerr<<"Unexpected response mode="<<i<<"\n";return 1;}
                size_t r=responses[i].front();responses[i].pop_front();response_count[i]++;
                if(bool((d.done>>i)&1)!=expected_done[r]){std::cerr<<"Wrong done mode="<<i<<" request="<<r<<"\n";return 1;}
                int tag=requests[r].id*2+requests[r].package;
                bool duplicate=i!=0 && result_sent[i][tag];
                if(expected_done[r] && !duplicate)outputs[i].push_back(r);
                if(expected_done[r] && duplicate)suppressed[i]++;
                if(i!=0){
                    if(requests[r].final)result_sent[i][tag]=false;
                    else if(expected_done[r])result_sent[i][tag]=true;
                }
            }
            Result value=read_result(i);
            if(stalled[i] && (!(d.m_valid&(1u<<i)) || !(held[i]==value))){std::cerr<<"Unstable parser output\n";return 1;}
            stalled[i]=(d.m_valid&(1u<<i)) && !(d.m_ready&(1u<<i));held[i]=value;
            if((d.m_valid&d.m_ready)&(1u<<i)){
                if(outputs[i].empty() || !(value==expected_result[outputs[i].front()])){std::cerr<<"Parser payload mismatch mode="<<i<<" cycle="<<cycle<<"\n";return 1;}
                outputs[i].pop_front();
            }
        }
        if(pending && accepted==255){next++;pending=false;}
        d.clk=1;d.eval();
        bool complete=next==requests.size();
        for(int i=0;i<8;i++)complete&=responses[i].empty()&&outputs[i].empty();
        if(complete && ++idle==10)break;
        if(!complete)idle=0;
    }
    for(int i=0;i<8;i++)if(response_count[i]!=int(requests.size())){std::cerr<<"Parser timeout mode="<<i<<"\n";return 1;}
    for(int i=1;i<8;i++)if(suppressed[i]==0){std::cerr<<"No duplicate-prefix coverage\n";return 1;}
    std::cout<<"PASS all 8 parser register combinations: "<<requests.size()<<" snapshots each, prefix suppression/tag reuse, response/data/error equivalence, gaps and independent backpressure\n";
}
