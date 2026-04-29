# Module Toggle — `/etc/etap/module.xml` 안전 편집

스크립트로 특정 모듈을 활성/비활성 전환할 때 사용. `sudo vi` 수동 편집이 불가능한 자동화 맥락(세션, hook, 반복 테스트)에서 필수.

---

## 핵심 원칙

1. **line-number 기반 `sed` 금지** — XML 포맷 변경에 취약. 한 번만 쓰고 버려도 다음 편집자가 동일 실수 반복.
2. **태그 + path 속성 기반 정확 매칭** — `libetap_{modname}.so` 경로로 식별.
3. **multi-line XML 블록 처리** — `<module` ... `/>`가 여러 줄에 걸쳐 있음. `re.DOTALL` 또는 sed `-z` 필요.
4. **변경 검증** — 실행 후 diff가 발생했는지 assert. no-op이면 오류 (이미 target 상태이거나 모듈 미존재).

---

## 권장 방식: python3 (Etap 서버 설치 확인됨)

```bash
# DISABLE — <module> → <_module>
ssh -p 12222 solution@61.79.198.110 'sudo python3 - <<EOF
import re, sys
MODNAME = "ai_prompt_filter"                 # 대상 모듈명 (libetap_{MODNAME}.so)
TARGET = "disable"                            # "disable" or "enable"
path = "/etc/etap/module.xml"
content = open(path).read()
if TARGET == "disable":
    # Use [^>] (not [^/]) — path attribute contains '/' (e.g. /usr/local/lib/etap/...)
    pat = re.compile(rf"<module(\s+[^>]*?libetap_{re.escape(MODNAME)}\.so[^>]*?/>)", re.DOTALL)
    repl = r"<_module\1"
else:
    pat = re.compile(rf"<_module(\s+[^>]*?libetap_{re.escape(MODNAME)}\.so[^>]*?/>)", re.DOTALL)
    repl = r"<module\1"
new = pat.sub(repl, content)
if new == content:
    sys.exit(f"ERROR: no change — {MODNAME} not found or already in target state ({TARGET})")
open(path, "w").write(new)
print(f"OK: {MODNAME} → {TARGET}")
EOF'
```

ENABLE은 동일 블록에서 `TARGET = "enable"`로 변경.

### 선택: 인자화된 wrapper

반복 사용 시 Etap 서버에 `/usr/local/bin/etap_module_toggle.py` 배치 후:
```bash
sudo etap_module_toggle.py ai_prompt_filter disable
sudo etap_module_toggle.py ai_prompt_filter enable
```

---

## 대안: GNU sed `-z` (null-delimited, multi-line)

sed에만 의존하는 환경에서:

```bash
# DISABLE
sudo sed -i -z \
  's|<module\(\s*\n\s*path="[^"]*libetap_ai_prompt_filter\.so"[^>]*\n\s*[^>]*\n\s*[^>]*/>\)|<_module\1|' \
  /etc/etap/module.xml
```

**주의**: 속성 라인 수 가정(`monitor=... log_level=... />`)에 종속. XML 포맷 변경 시 깨짐. python3 방식 선호.

---

## 필수 후속 절차

모듈 토글 후 반드시:

```bash
sudo systemctl restart etapd.service
sleep 10                                  # DPDK 재초기화
pgrep -xc etap                            # 반드시 1
ping -c 3 192.168.200.100                 # Dell 간 브릿지 복구 (Dell-1에서)
etapcomm {모듈}.show_config 2>&1 | head   # enable 시 동작 확인 / disable 시 "Module does not exist"
```

- 인스턴스 수 ≠ 1 → `sudo pkill -x etap && sudo systemctl restart etapd.service`
- ping 실패 → `references/troubleshooting.md` 참조

---

## 검증된 토글 대상 (v2.2.2 기준)

`/etc/etap/module.xml`의 모든 엔트리가 토글 가능하지만, 테스트베드에서 검증된 조합:

| 모듈 | path fragment | 비활성화 영향 | 참조 |
|------|---------------|---------------|------|
| `ai_prompt_filter` | `libetap_ai_prompt_filter.so` | APF 차단 무효화, VT/HTTP 정상 | `decisive-functional-proofs.md §2` |
| `visible_tls` | `libetap_visible_tls.so` | TLS MITM 무효화, HTTPS bypass 상태 | `vt-test-guide.md` |

다른 모듈(`tcpip`, `http`, `dns` 등)은 비활성화 시 브릿지 전체가 중단될 수 있어 **testbed에서 검증하지 않음**.
