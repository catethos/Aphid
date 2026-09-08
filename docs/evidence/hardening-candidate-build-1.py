import hashlib,json,shlex,subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path.cwd()/'scripts'))
from proof import ROOT,run
build=ROOT/'_build/sanitizers-clt21/ladybug'
out=ROOT/'_build/hardening-candidate-asan';out.mkdir(exist_ok=False)
commands=subprocess.check_output(['ninja','-t','commands','src/liblbug.dylib'],cwd=build,text=True).splitlines()
link=shlex.split(next(c for c in commands if ' -o src/liblbug.' in c))[2:-2]
link[link.index('-o')+1]=str(out/'liblbug.0.dylib')
for relative,patch in [
 ('src/processor/operator/order_by/order_by_key_encoder.cpp','float-sort-key-alignment'),
 ('src/common/types/int128_t.cpp','int128-add-carry')]:
 p=out/relative;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((ROOT/'native/upstream/ladybug'/relative).read_bytes())
 run(['git','apply',str(ROOT/('native/patches/candidates/'+patch+'.patch'))],cwd=out)
 command=shlex.split(next(c for c in commands if '/'+relative in c and ' -c ' in c))
 old_object=command[command.index('-o')+1]
 command[command.index('-c')+1]=str(p)
 obj=out/(patch+'.o')
 command[command.index('-o')+1]=str(obj)
 command[command.index('-MF')+1]=str(out/(patch+'.d'))
 run(command,cwd=build)
 assert old_object in link
 link=[str(obj) if arg==old_object else arg for arg in link]
# Use the retained, previously verified atomic-FTS object, never shared archives.
fts=ROOT/'_build/fts-candidate-sanitizers-clt21'
assert (fts/'fts/src/function/create_fts_index.cpp').read_bytes()==(ROOT/'native/upstream/ladybug/extension/fts/src/function/create_fts_index.cpp').read_bytes()
for original in sorted(set(arg for arg in link if arg.endswith('_static.lbug_extension'))):
 tokens=shlex.split(next(c for c in commands if 'ar qc '+original in c))
 start=tokens.index('qc')+2; end=tokens.index('&&',start);members=tokens[start:end]
 if 'libfts_static' in original:
  assert sum(x.endswith('/create_fts_index.cpp.o') for x in members)==1
  members=[str(fts/'create_fts_index.cpp.o') if x.endswith('/create_fts_index.cpp.o') else x for x in members]
 archive=out/Path(original).name
 run(['ar','qc',str(archive),*members],cwd=build);run(['ranlib',str(archive)])
 link=[str(archive) if arg==original else arg for arg in link]
run(link,cwd=build)
for p in [ROOT/'native/lock.json',*sorted((ROOT/'native/patches/candidates').glob('*.patch')),fts/'create_fts_index.cpp.o',*sorted(out.glob('*.o')),out/'liblbug.0.dylib']:
 print(json.dumps({'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}),flush=True)
