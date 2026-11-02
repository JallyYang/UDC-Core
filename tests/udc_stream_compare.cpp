#include "Vcompare.h"
#include "verilated.h"
#include "core_reset_check.h"
#include <array>
#include <deque>
#include <random>
#include <iostream>
#include <string>
int run_performance(int argc,char**argv);
struct Unit {std::array<unsigned,32> data;int fmt,limit;};
struct Beat {std::array<unsigned,8> data;int sop,last,has,mode;bool operator==(const Beat&)const=default;};
int main(int argc,char**argv){if(argc>1 && std::string(argv[1])=="--performance")return run_performance(argc,argv);Verilated::commandArgs(argc,argv);Vcompare d;std::mt19937 rng(94217);std::array<Unit,512> units;
for(int u=0;u<512;u++){units[u].fmt=u%16;int limits[]={0,1,32,64,68,127};units[u].limit=limits[(u/16)%6];for(int j=0;j<32;j++)units[u].data[j]=u%5==0?0x10203040+(u%10)+(j%4):u%5==1?0:u%5==2?(j/4):rng();}
for(int i=0;i<10;i++)for(int j=0;j<4;j++)d.cfg_clear_pattern[i*4+j]=0x10203040+i+j;
d.r_s_valid=0;d.r_m_ready=0;
if (!check_reset_recovery(d,
    {d.n_s_valid,d.n_s_ready,d.n_s_sop,d.n_s_last,d.n_s_data,
     d.n_m_valid,d.n_m_ready,d.n_m_sop,d.n_m_last,d.n_m_data}, 4,
    [&](bool raw) { d.n_s_udc_format=10; d.n_s_package_size_limit=raw?0:68; },
    [&] { return d.n_m_has_data && d.n_m_cbmd==0; })) return 1;
d.rst_n=0;d.n_s_valid=0;d.r_s_valid=0;d.n_m_ready=0;d.r_m_ready=0;for(int i=0;i<3;i++){d.clk=0;d.eval();d.clk=1;d.eval();}d.rst_n=1;
int nt=0,rt=0,nb=0,rb=0,nout=0,rout=0,matched=0;bool np=false,rp=false,ns=false,rs=false;Beat nh{},rh{};std::deque<Beat> nq,rq;
for(int cycle=0;cycle<100000 && (nout<512||rout<512);cycle++){
d.clk=0;if(!np&&nt<512&&rng()%4)np=true;if(!rp&&rt<512&&rng()%4)rp=true;d.n_s_valid=np;d.r_s_valid=rp;d.n_m_ready=rng()%4!=0;d.r_m_ready=rng()%4!=0;
if(nt<512){d.n_s_sop=nb==0;d.n_s_last=nb==3;d.n_s_udc_format=units[nt].fmt;d.n_s_package_size_limit=units[nt].limit;for(int j=0;j<8;j++)d.n_s_data[j]=units[nt].data[nb*8+j];}
if(rt<512){d.r_s_sop=rb==0;d.r_s_last=rb==3;d.r_s_udc_format=units[rt].fmt;d.r_s_package_size_limit=units[rt].limit;for(int j=0;j<8;j++)d.r_s_data[j]=units[rt].data[rb*8+j];}
d.eval();Beat n{},r{};for(int j=0;j<8;j++){n.data[j]=d.n_m_data[j];r.data[j]=d.r_m_data[j];}n.sop=d.n_m_sop;n.last=d.n_m_last;n.has=d.n_m_has_data;n.mode=d.n_m_cbmd;r.sop=d.r_m_sop;r.last=d.r_m_last;r.has=d.r_m_has_data;r.mode=d.r_m_cbmd;
if((ns&&(!d.n_m_valid||!(n==nh)))||(rs&&(!d.r_m_valid||!(r==rh)))){std::cerr<<"unstable output\n";return 1;}
ns=d.n_m_valid&&!d.n_m_ready;rs=d.r_m_valid&&!d.r_m_ready;nh=n;rh=r;
if(d.n_m_valid&&d.n_m_ready){nq.push_back(n);if(n.last)nout++;}if(d.r_m_valid&&d.r_m_ready){rq.push_back(r);if(r.last)rout++;}
while(!nq.empty()&&!rq.empty()){if(!(nq.front()==rq.front())){std::cerr<<"Mismatch beat="<<matched<<" newmode="<<nq.front().mode<<" oldmode="<<rq.front().mode<<"\n";return 1;}nq.pop_front();rq.pop_front();matched++;}
if(np&&d.n_s_ready){np=false;if(++nb==4){nb=0;nt++;}}if(rp&&d.r_s_ready){rp=false;if(++rb==4){rb=0;rt++;}}
d.clk=1;d.eval();}
if(nout!=512||rout!=512||!nq.empty()||!rq.empty()){std::cerr<<"Timeout "<<nt<<" "<<nout<<" "<<rt<<" "<<rout<<"\n";return 1;}
std::cout<<"PASS 512 encoder units bit-exact against baseline, mixed formats/limits/Clear, input gaps, output stalls, slot reuse; beats="<<matched<<"\n";}
