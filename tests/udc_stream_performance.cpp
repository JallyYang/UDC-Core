#include "Vcompare.h"
#include "verilated.h"
#include <iostream>
int run_performance(int argc,char**argv) {
 Verilated::commandArgs(argc,argv);
 for(int test=0;test<18;test++) {
  int fmt=test<14?test+1:test==14?0:test==15?15:1;
  int expected_fmt=fmt>=1&&fmt<=14?fmt:10;
  bool clear=test==17, raw=test==16;
  Vcompare d;
  for(int i=0;i<10;i++)for(int j=0;j<4;j++)d.cfg_clear_pattern[i*4+j]=0x10203040+i+j;
  d.r_s_valid=0;d.r_m_ready=1;d.rst_n=0;d.n_s_valid=0;d.n_m_ready=1;
  for(int i=0;i<3;i++){d.clk=0;d.eval();d.clk=1;d.eval();}
  d.rst_n=1;
  int tx=0,rx=0,beat=0,first=-1,last_input=-1,stalls=0,outputs=0;
  for(int cycle=0;cycle<20000&&rx<128;cycle++) {
   d.clk=0;d.n_s_valid=tx<128;d.n_s_sop=beat==0;d.n_s_last=beat==3;
   d.n_s_udc_format=fmt;d.n_s_package_size_limit=raw?0:68;
   for(int j=0;j<8;j++)d.n_s_data[j]=clear?0x10203040+(j%4):0;
   d.eval();
   if(d.n_m_valid&&d.n_m_ready) {
    if(first<0)first=cycle;
    if(d.n_m_sop) {
     if(clear ? (d.n_m_cbmd!=6||d.n_m_has_data) : raw ? (d.n_m_cbmd!=0||!d.n_m_has_data) : (d.n_m_cbmd<1||d.n_m_cbmd>5||((d.n_m_data[0]>>2)&15)!=unsigned(expected_fmt)))return 1;
    }
    if(raw)for(int j=0;j<8;j++)if(d.n_m_data[j])return 1;
    outputs++;if(d.n_m_last)rx++;
   }
   if(d.n_s_valid&&!d.n_s_ready)stalls++;
   if(d.n_s_valid&&d.n_s_ready){last_input=cycle;if(++beat==4){beat=0;tx++;}}
   d.clk=1;d.eval();
  }
  int expected_first=raw?7:9;
  if(rx!=128||first!=expected_first||last_input!=511||stalls!=0){std::cerr<<"encoder perf failed test="<<test<<" first="<<first<<" last_input="<<last_input<<" stalls="<<stalls<<" rx="<<rx<<"\n";return 1;}
  std::cout<<"PASS encoder fmt="<<fmt<<" raw="<<raw<<" clear="<<clear<<" first="<<first<<" last_input="<<last_input<<" input_stalls="<<stalls<<" units="<<rx<<" output_beats="<<outputs<<"\n";
 }
 return 0;
}
