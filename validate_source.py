"""Small release-source checks; does not replace a security review or device test."""
from pathlib import Path
import ast, json, re

ROOT = Path(__file__).resolve().parent


def main():
    m = (ROOT / 'src/PinkCatAudio.m').read_text(encoding='utf-8')
    policy = (ROOT / 'src/PanelPolicy.h').read_text(encoding='utf-8')
    assert 'Button(w,"pink cat"' in m
    assert 'Wi-Fi' not in m and '手机麦' not in m and 'PC %d' not in m
    assert 'PC 正式版请联系' in m
    assert 'monnight1' in policy and 'aze-070130' in policy
    assert 'S("copyContact:"),(IMP)CopyContact' in m
    assert 'S("setContentSize:")' in m and '"safeAreaInsets"' in m
    assert 'O(panel,"superview")==w' in m
    assert 'VB(floating,"setHidden:",hidden)' in m
    assert 'PCSavedRate(Kind(saved,"NSNumber")' in m
    copy = m.split('static void CopyContact(', 1)[1].split('static PCInsets', 1)[0]
    assert '"setString:"' in copy and '"string"' not in copy and 'openURL' not in copy
    assert 'TEST' not in m.split('static void BuildPanel(', 1)[1].split('static void Tick(', 1)[0]
    for p in ROOT.glob('*.py'):
        ast.parse(p.read_text(encoding='utf-8'), filename=p.name)
    suspicious = []
    forbidden = {'.pem', '.key', '.ipa', '.p12', '.pfx', '.sqlite', '.db', '.exe'}
    for d in ['src', 'tests', 'link-stubs']:
        for p in (ROOT / d).rglob('*'):
            if not p.is_file():
                continue
            if p.suffix.lower() in forbidden:
                suspicious.append(str(p.relative_to(ROOT)))
            if p.suffix in ['.h', '.m', '.c', '.py']:
                text = p.read_text(encoding='utf-8')
                assert not re.search(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', text)
    assert not suspicious, suspicious
    result = {'status': 'PASS', 'brandAndContacts': 'PASS', 'copyHandlerWiring': 'STATIC_PASS',
              'safeAreaAndScrollWiring': 'STATIC_PASS', 'oldTestLabelsInUI': False,
              'pythonSyntax': 'PASS', 'secretAndBinaryScreen': 'allowlist plus limited patterns; not exhaustive',
              'UIKitTouchAndRendering': 'NOT_RUN'}
    dest = ROOT / 'build/source-validation.json'
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=True))


if __name__ == '__main__':
    main()
