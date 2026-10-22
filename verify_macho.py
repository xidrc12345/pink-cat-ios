from pathlib import Path
import argparse,struct,hashlib,json

def verify(path):
    b=Path(path).read_bytes();u=lambda p:struct.unpack_from('<I',b,p)[0]
    assert len(b)>4096 and u(0)==0xfeedfacf,'Not a 64-bit Mach-O'
    assert u(4)==0x100000c and u(12)==6,'Not an arm64 dylib'
    pos=32;sections=[];imports=[];exports=[];libs=[];ident=None;build=None;signature=None;constructor=False
    for _ in range(u(16)):
        cmd,size=u(pos),u(pos+4);assert size>=8 and pos+size<=len(b)
        if cmd==0x19:
            name=b[pos+8:pos+24].split(b'\0',1)[0].decode();initprot=u(pos+60)
            assert initprot&6!=6,'Writable executable segment'
            n=u(pos+64)
            for j in range(n):
                at=pos+72+j*80;sec=b[at:at+16].split(b'\0',1)[0].decode();sections.append((name,sec))
                if sec in ['__mod_init_func','__init_offsets']:constructor=True
        elif cmd in [0xc,0xd]:
            start=pos+u(pos+8);name=b[start:b.index(0,start)].decode()
            if cmd==0xd:ident=name
            else:libs.append(name)
        elif cmd==0x32:build={'platform':u(pos+8),'minOS':u(pos+12),'sdk':u(pos+16)}
        elif cmd==0x1d:signature=(u(pos+8),u(pos+12))
        elif cmd==2:
            off,count,strings,strlen=struct.unpack_from('<4I',b,pos+8)
            for j in range(count):
                string_index,kind,section,desc,value=struct.unpack_from('<IBBHQ',b,off+j*16)
                if not string_index:continue
                end=b.index(0,strings+string_index);name=b[strings+string_index:end].decode()
                if kind&0xe==0 and kind&1:imports.append(name)
                elif kind&0xe==0xe and kind&1:exports.append(name)
        pos+=size
    assert ident=='@rpath/PinkCatAudio.dylib' and constructor
    assert build and build['platform']==2 and build['minOS']==0x100000,'Wrong deployment target'
    assert '_PinkCatAudioState' in exports,'Missing MCP-readable state export'
    assert signature,'No ad-hoc signature'
    sig=signature[0];magic,length,count=struct.unpack_from('>3I',b,sig);assert magic==0xfade0cc0
    cds=[]
    for i in range(count):
        slot,offset=struct.unpack_from('>2I',b,sig+12+i*8)
        if slot==0:cds.append(sig+offset)
    assert len(cds)==1
    cd=cds[0];magic,length,version,flags,hashoff,identoff,special,slots,limit=struct.unpack_from('>9I',b,cd)
    hashsize,hashtype,platform,page=struct.unpack_from('4B',b,cd+36)
    assert magic==0xfade0c02 and flags&2 and hashtype==2 and hashsize==32
    for i in range(slots):
        digest=hashlib.sha256(b[i*(1<<page):min((i+1)*(1<<page),limit)]).digest()
        assert digest==b[cd+hashoff+i*hashsize:cd+hashoff+(i+1)*hashsize],'Code signature page mismatch'
    return {'status':'PASS','bytes':len(b),'architecture':'arm64','platform':'iOS','minimumOS':'16.0','type':'MH_DYLIB','installName':ident,'constructor':True,'adHocCodePagesVerified':slots,'writeExecuteSegments':False,'sha256':hashlib.sha256(b).hexdigest(),'imports':sorted(imports),'exports':sorted(exports),'dependencies':libs,'runtimeInjection':'NOT_RUN','sustained192kbps':'NOT_VERIFIED','receiverAudio':'NOT_VERIFIED','UIKitTouchAndRendering':'NOT_RUN'}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('dylib',type=Path);p.add_argument('--out',type=Path);a=p.parse_args();r=verify(a.dylib)
    if a.out:a.out.write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(r,ensure_ascii=True,indent=2))
