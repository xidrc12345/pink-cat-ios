"""Host-side assertions, not an iOS simulator or device acceptance test."""
from pathlib import Path
import argparse, ctypes, json, os, subprocess, sys

ROOT = Path(__file__).resolve().parent


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--llvm-bin', type=Path, required=True)
    a = p.parse_args()
    if os.name != 'nt' or ctypes.sizeof(ctypes.c_void_p) != 8:
        raise SystemExit('This freestanding mock runner requires 64-bit Windows/Python. iOS build is separate.')
    tools = a.llvm_bin.resolve()
    build = ROOT / 'build' / 'tests'
    build.mkdir(parents=True, exist_ok=True)
    tests = [('panel', ROOT / 'tests/panel_test.c'), ('native', ROOT / 'src/native_mock_test.c')]
    report = {'status': 'PASS', 'scope': 'host mocks only; no UIKit or iOS runtime', 'suites': []}
    crt = ctypes.CDLL('msvcrt.dll')
    for name, src in tests:
        obj, dll = build / f'{name}.obj', build / f'{name}.dll'
        commands = [
            [tools / 'clang.exe', '-O2', '-c', '-fno-builtin', '-fno-stack-protector', src, '-o', obj],
            [tools / 'ld.lld.exe', '-flavor', 'link', '/dll', '/noentry', f'/out:{dll}', obj],
        ]
        for n, cmd in enumerate(commands):
            r = subprocess.run(list(map(str, cmd)), capture_output=True)
            (build / f'{name}-{n}.log').write_bytes(r.stdout + b'\n' + r.stderr)
            if r.returncode:
                raise SystemExit(f'{name} compile/link failed: {build / f"{name}-{n}.log"}')
        lib = ctypes.CDLL(str(dll))
        if name == 'panel':
            ctypes.c_void_p.in_dll(lib, 'pc_snprintf').value = ctypes.cast(crt._snprintf, ctypes.c_void_p).value
        lib.run_tests.restype = ctypes.c_int
        count = lib.run_tests()
        failed = ctypes.c_char_p.in_dll(lib, 'failedExpression').value
        if count <= 0 or failed:
            report['status'] = 'FAIL'
        report['suites'].append({'name': name, 'assertions': count, 'failed': failed.decode('utf-8') if failed else None})
    report['assertions'] = sum(max(0, x['assertions']) for x in report['suites'])
    # Core encoder implementation is intentionally unchanged from the 192-only build.
    report['runtimeInjection'] = 'NOT_RUN'
    report['receiverAudio'] = 'NOT_VERIFIED'
    (build.parent / 'tests.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=True))
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
