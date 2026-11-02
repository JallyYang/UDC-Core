from pathlib import Path
import re,subprocess
import sys
r=Path(__file__).resolve().parents[1];d=Path(sys.argv[1]).resolve();d.mkdir(parents=True,exist_ok=True);old=d/'old';old.mkdir(exist_ok=True)
files=[]
for p in (r/'rtl').glob('udc_*.sv'):
 if p.name=='udc_enc_stream.sv':continue
 text=subprocess.check_output(['git','show','b732757:rtl/'+p.name],cwd=r,text=True)
 text=re.sub(r'\budc_(\w+)',r'ref_udc_\1',text)
 out=old/p.name;out.write_text(text);files.append(str(out))
s=(r/'rtl/udc_enc_core.sv').read_text();ports=s[s.index('        input logic clk'):s.index('    );')]
lines=[];conns={}
for prefix in ['n','r']:
 conns[prefix]=[]
 for line in ports.splitlines():
  match=re.search(r'(\w+),?$',line.strip())
  if not match:continue
  name=match[1];renamed=name if name in ['clk','rst_n','cfg_clear_pattern'] else prefix+'_'+name
  if prefix=='n' or name not in ['clk','rst_n','cfg_clear_pattern']:lines.append(re.sub(r'\b'+name+r'\b',renamed,line.strip().rstrip(',')))
  conns[prefix].append(f'.{name}({renamed})')
wrapper='module compare #(parameter int unsigned UNIT_ID_W=4, parameter int unsigned UNIT_SLOTS=4) (\n'+',\n'.join(lines)+'\n);\n'
for prefix,mod in [('n','udc_enc_core'),('r','ref_udc_enc_core')]:wrapper+=mod+' #(.UNIT_SLOTS(UNIT_SLOTS)) '+prefix+' ('+', '.join(conns[prefix])+');\n'
wrapper+='endmodule\n';(d/'compare.sv').write_text(wrapper);(d/'old.f').write_text('\n'.join(files)+'\n')
