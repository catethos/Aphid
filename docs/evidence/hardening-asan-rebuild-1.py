import hashlib,json,shutil,sys
from pathlib import Path
sys.path.insert(0,str(Path.cwd()/'scripts'))
from proof import ROOT,run
out=ROOT/'_build/hardening-asan';out.mkdir(exist_ok=False)
source=out/'source'
shutil.copytree(ROOT/'_build/tsan-clt21/source',source,ignore=shutil.ignore_patterns('build'))
assert (ROOT/'_build/tsan-clt21/lock.json').read_bytes()==(ROOT/'native/lock.json').read_bytes()
for patch in sorted((ROOT/'native/patches/candidates').glob('*.patch')):
 run(['git','apply',str(patch)],cwd=source)
 print(json.dumps({'patch':str(patch),'sha256':hashlib.sha256(patch.read_bytes()).hexdigest()}),flush=True)
shutil.copy2(ROOT/'native/lock.json',out/'base-lock.json')
common=['-G','Ninja','-DCMAKE_BUILD_TYPE=Release','-DCMAKE_OSX_DEPLOYMENT_TARGET=13.3','-DCMAKE_EXPORT_COMPILE_COMMANDS=ON',f'-DCMAKE_TOOLCHAIN_FILE={ROOT / "native/cmake/sanitizer-clt21.cmake"}']
flags='-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer'
common += [f'-DCMAKE_C_FLAGS={flags}',f'-DCMAKE_CXX_FLAGS={flags}']
install=ROOT/'_build/native/install'
run(['cmake','-S',str(source),'-B',str(out/'ladybug'),*common,'-DBUILD_SHELL=OFF','-DBUILD_TESTS=OFF','-DBUILD_SINGLE_FILE_HEADER=OFF','-DEXTENSION_STATIC_LINK_LIST=fts;vector;duckdb','-DBUILD_SHARED_LBUG=ON','-DBUILD_STATIC_LBUG=ON',f'-DDuckDB_DIR={ROOT / "_build/sanitizers-clt21/duckdb"}',f'-DOPENSSL_ROOT_DIR={install}','-DOPENSSL_USE_STATIC_LIBS=ON',f'-DOPENSSL_SSL_LIBRARY={install / "lib/libssl.a"}',f'-DOPENSSL_CRYPTO_LIBRARY={install / "lib/libcrypto.a"}',f'-DOPENSSL_INCLUDE_DIR={install / "include"}'])
run(['cmake','--build',str(out/'ladybug'),'--parallel','2'],timeout=7200)
run(['cmake','-S','native','-B',str(out/'bridge'),*common,f'-DLADYBUG_SOURCE={source}',f'-DLADYBUG_BUILD={out / "ladybug"}','-DAPHID_BUILD_TESTS=ON'])
run(['cmake','--build',str(out/'bridge'),'--parallel','2'],timeout=120)
