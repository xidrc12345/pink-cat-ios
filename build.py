from pathlib import Path
import argparse,subprocess,os,json
ROOT=Path(__file__).resolve().parent

def main():
    p=argparse.ArgumentParser(description='Build pink cat arm64 iOS dylib locally; no injection or device changes.')
    p.add_argument('--llvm-bin',type=Path,required=True);p.add_argument('--out',type=Path,default=ROOT/'build/PinkCatAudio.dylib');a=p.parse_args()
    tools=a.llvm_bin.resolve();suffix='.exe' if os.name=='nt' else '';clang=tools/('clang'+suffix);linker=tools/('ld64.lld'+suffix);flavor=[]
    if not linker.is_file():linker=tools/('ld.lld'+suffix);flavor=['-flavor','darwin']
    if not clang.is_file() or not linker.is_file():raise SystemExit('Need an LLVM clang and Darwin-capable LLD binary')
    out=a.out.resolve();out.parent.mkdir(parents=True,exist_ok=True);obj=out.with_suffix('.o');stub=ROOT/'link-stubs'
    commands=[
        [clang,'--target=arm64-apple-ios16.0','-x','objective-c','-O2','-fobjc-exceptions','-fno-objc-arc','-fno-stack-protector','-fvisibility=hidden','-Wall','-Wextra','-Wno-cast-function-type-mismatch','-c',ROOT/'src/PinkCatAudio.m','-o',obj],
        [linker,*flavor,'-dylib','-arch','arm64','-platform_version','ios','16.0','16.0','-undefined','dynamic_lookup','-install_name','@rpath/PinkCatAudio.dylib','-adhoc_codesign','-o',out,obj,'-L'+str(stub),'-lSystem']
    ]
    record=[]
    for i,cmd in enumerate(commands):
        r=subprocess.run(list(map(str,cmd)),capture_output=True);(out.parent/('build-'+str(i)+'.log')).write_bytes(r.stdout+b'\nSTDERR\n'+r.stderr)
        record.append({'stage':'compile' if i==0 else 'link','exitCode':r.returncode})
        if r.returncode:raise SystemExit('Build failed; inspect '+str(out.parent/('build-'+str(i)+'.log')))
    (out.parent/'build-result.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
    print('BUILT '+str(out)+'; device injection not executed')

if __name__=='__main__':main()
