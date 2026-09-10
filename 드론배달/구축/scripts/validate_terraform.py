# -*- coding: utf-8 -*-
"""Terraform 정적 검증 — `terraform validate` 를 실행하기 «전»에 도는 방어선.

왜 필요한가
    `terraform validate` 는 프로바이더를 내려받아야 하고(init), Terraform 1.9 이상이 필요하다.
    이 스크립트는 파이썬만 있으면 돌아가므로, 도구가 준비되지 않은 환경에서도
    가장 흔한 실수를 잡아낸다.

검사 항목
    ① 모듈 참조    envs 가 부르는 모듈이 실제로 존재하는가
    ② 변수 선언    모듈에 전달하는 인수가 그 모듈의 variable 로 선언되어 있는가
    ③ 출력 참조    module.x.y 로 읽는 출력이 그 모듈에 정의되어 있는가
    ④ 필수 변수    기본값 없는 변수가 tfvars.example 에 있는가
    ⑤ 보안 규칙    0.0.0.0/0 · 하드코딩 비밀 · latest 태그 · 구독 범위 역할
    ⑥ 태그 필수    모든 리소스가 tags 를 받는가 (비용 추적)
    ⑦ 드리프트     timestamp() 같은 «매번 바뀌는» 함수 사용

사용법
    python validate_terraform.py [terraform 루트 경로]
"""
import io
import os
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', 'terraform')
ROOT = os.path.abspath(ROOT)

failures = []
warnings = []


def fail(check, message):
    failures.append((check, message))


def warn(check, message):
    warnings.append((check, message))


def read(path):
    return io.open(path, encoding='utf-8').read()


def tf_files(directory):
    if not os.path.isdir(directory):
        return []
    return [os.path.join(directory, f) for f in os.listdir(directory) if f.endswith('.tf')]


def read_dir(directory):
    return '\n'.join(read(f) for f in tf_files(directory))


# ═════════════════════════════════════════════════════════ 수집

def collect_module_interface(module_dir):
    """모듈의 variable · output 이름을 모은다."""
    src = read_dir(module_dir)
    variables = {}
    for m in re.finditer(r'variable\s+"([^"]+)"\s*\{', src):
        name = m.group(1)
        # 블록 본문에서 default 유무를 본다
        start = m.end()
        depth = 1
        i = start
        while i < len(src) and depth > 0:
            if src[i] == '{':
                depth += 1
            elif src[i] == '}':
                depth -= 1
            i += 1
        body = src[start:i]
        variables[name] = 'default' in body
    outputs = set(re.findall(r'output\s+"([^"]+)"\s*\{', src))
    return variables, outputs


modules_dir = os.path.join(ROOT, 'modules')
modules = {}
if os.path.isdir(modules_dir):
    for name in sorted(os.listdir(modules_dir)):
        d = os.path.join(modules_dir, name)
        if os.path.isdir(d):
            modules[name] = collect_module_interface(d)

envs_dir = os.path.join(ROOT, 'envs')
envs = sorted(os.listdir(envs_dir)) if os.path.isdir(envs_dir) else []

print('=' * 66)
print(' Terraform 정적 검증')
print('=' * 66)
print(' 경로     %s' % ROOT)
print(' 모듈     %d개 — %s' % (len(modules), ', '.join(modules)))
print(' 환경     %d개 — %s' % (len(envs), ', '.join(envs)))
print()


# ═════════════════════════════════════════════════════════ ① ~ ③

MODULE_CALL = re.compile(
    r'module\s+"([^"]+)"\s*\{(.*?)\n\}', re.S)

for env in envs:
    env_dir = os.path.join(envs_dir, env)
    src = read_dir(env_dir)

    called = {}
    for m in MODULE_CALL.finditer(src):
        alias, body = m.group(1), m.group(2)

        source = re.search(r'source\s*=\s*"([^"]+)"', body)
        if not source:
            fail('①모듈참조', '%s: module "%s" 에 source 가 없습니다' % (env, alias))
            continue

        module_name = os.path.basename(source.group(1).rstrip('/'))
        called[alias] = module_name

        if module_name not in modules:
            fail('①모듈참조', '%s: module "%s" 가 참조하는 %s 모듈이 없습니다'
                 % (env, alias, module_name))
            continue

        declared_vars, _ = modules[module_name]

        # ② 전달 인수가 선언되어 있는가
        for arg in re.findall(r'^\s{2}([a-z_][a-z0-9_]*)\s*=', body, re.M):
            if arg == 'source':
                continue
            if arg not in declared_vars:
                fail('②변수선언', '%s: module "%s" 에 없는 인수를 전달합니다 → %s'
                     % (env, module_name, arg))

        # 필수 변수(기본값 없음)를 빠뜨리지 않았는가
        passed = set(re.findall(r'^\s{2}([a-z_][a-z0-9_]*)\s*=', body, re.M))
        for var_name, has_default in declared_vars.items():
            if not has_default and var_name not in passed:
                fail('②변수선언', '%s: module "%s" 의 필수 변수 %s 를 전달하지 않았습니다'
                     % (env, module_name, var_name))

    # ③ module.<alias>.<output> 참조 확인
    for alias, output in re.findall(r'module\.([a-z_][a-z0-9_]*)\.([a-z_][a-z0-9_]*)', src):
        if alias not in called:
            fail('③출력참조', '%s: 선언되지 않은 module.%s 를 참조합니다' % (env, alias))
            continue
        module_name = called[alias]
        if module_name not in modules:
            continue
        _, declared_outputs = modules[module_name]
        if output not in declared_outputs:
            fail('③출력참조', '%s: %s 모듈에 없는 출력을 참조합니다 → module.%s.%s'
                 % (env, module_name, alias, output))


# ═════════════════════════════════════════════════════════ ④ 필수 변수 vs tfvars

for env in envs:
    env_dir = os.path.join(envs_dir, env)
    env_vars, _ = collect_module_interface(env_dir)
    required = {n for n, has_default in env_vars.items() if not has_default}

    example = os.path.join(env_dir, 'terraform.tfvars.example')
    if not os.path.exists(example):
        if required:
            fail('④필수변수', '%s: 필수 변수 %d개가 있는데 tfvars.example 이 없습니다'
                 % (env, len(required)))
        continue

    provided = set(re.findall(r'^\s*([a-z_][a-z0-9_]*)\s*=', read(example), re.M))
    for name in sorted(required - provided):
        fail('④필수변수', '%s: 필수 변수 %s 가 tfvars.example 에 없습니다' % (env, name))


# ═════════════════════════════════════════════════════════ ⑤ 보안 규칙

SECURITY_RULES = [
    # (정규식, 검사명, 메시지, 예외 파일 패턴)
    (re.compile(r'"0\.0\.0\.0/0"'), 'A-09 방화벽',
     '0.0.0.0/0 을 허용하고 있습니다', ('gateway',)),
    (re.compile(r':latest["\s]'), 'A-10 이미지 태그',
     'latest 태그를 쓰고 있습니다', ()),
    (re.compile(r'role_definition_name\s*=\s*"(Contributor|Owner)"'), 'A-02 과도한 역할',
     'Contributor 또는 Owner 역할을 부여하고 있습니다', ()),
    (re.compile(r'scope\s*=\s*"/subscriptions/[^/"]+"\s*$', re.M), 'A-01 구독 범위',
     '구독 범위로 역할을 부여하고 있습니다', ()),
    (re.compile(r'(password|secret|connection_string|access_key)\s*=\s*"[^"$\s]{8,}"',
                re.I), 'A-05 하드코딩 비밀',
     '비밀로 보이는 값을 하드코딩했습니다', ()),
    (re.compile(r'admin_enabled\s*=\s*true'), 'ACR 관리자 계정',
     'ACR 관리자 계정이 켜져 있습니다 — 관리 ID 를 쓰세요', ()),
]

for root, _, files in os.walk(ROOT):
    if '.terraform' in root:
        continue
    for name in files:
        if not name.endswith('.tf'):
            continue
        path = os.path.join(root, name)
        rel = os.path.relpath(path, ROOT)
        src = read(path)

        # 주석은 검사 대상에서 뺀다 — 설명문에 «0.0.0.0/0 금지» 라고 쓴 것을 잡으면 안 된다
        code = '\n'.join(l for l in src.split('\n')
                         if not l.strip().startswith('#'))

        for pattern, check, message, exempt in SECURITY_RULES:
            if any(e in rel for e in exempt):
                continue
            if pattern.search(code):
                fail('⑤보안', '%s: %s — %s' % (rel, check, message))


# ═════════════════════════════════════════════════════════ ⑥ 태그

RESOURCE = re.compile(r'resource\s+"(azurerm_[a-z0-9_]+)"\s+"([^"]+)"\s*\{(.*?)\n\}', re.S)

# 태그를 지원하지 않는 리소스 유형
NO_TAGS = {
    'azurerm_subnet', 'azurerm_network_security_rule',
    'azurerm_subnet_network_security_group_association',
    'azurerm_role_assignment', 'azurerm_cosmosdb_sql_role_assignment',
    'azurerm_storage_container', 'azurerm_servicebus_queue',
    'azurerm_eventhub', 'azurerm_eventhub_consumer_group',
    'azurerm_cosmosdb_sql_database', 'azurerm_cosmosdb_sql_container',
    'azurerm_cosmosdb_mongo_database', 'azurerm_management_lock',
    'azurerm_spring_cloud_app', 'azurerm_spring_cloud_java_deployment',
    'azurerm_spring_cloud_active_deployment', 'azurerm_virtual_network_peering',
    'azurerm_private_dns_zone_virtual_network_link',
    'azurerm_consumption_budget_resource_group',
}

for root, _, files in os.walk(ROOT):
    if '.terraform' in root:
        continue
    for name in files:
        if not name.endswith('.tf'):
            continue
        path = os.path.join(root, name)
        rel = os.path.relpath(path, ROOT)
        for m in RESOURCE.finditer(read(path)):
            rtype, rname, body = m.groups()
            if rtype in NO_TAGS:
                continue
            if 'tags' not in body:
                warn('⑥태그', '%s: %s.%s 에 tags 가 없습니다 — 비용 추적이 불가능합니다'
                     % (rel, rtype, rname))


# ═════════════════════════════════════════════════════════ ⑦ 드리프트 유발

DRIFT = re.compile(r'\b(timestamp|uuid)\s*\(\s*\)')

for root, _, files in os.walk(ROOT):
    if '.terraform' in root:
        continue
    for name in files:
        if not name.endswith('.tf'):
            continue
        path = os.path.join(root, name)
        # 주석과 description 문구는 «코드»가 아니다.
        # 설명문에 «timestamp() 를 쓰지 마라» 라고 적은 것을 위반으로 잡으면 안 된다.
        code = '\n'.join(l for l in read(path).split('\n')
                         if not l.strip().startswith('#')
                         and not re.match(r'\s*description\s*=', l))
        if DRIFT.search(code):
            fail('⑦드리프트', '%s: timestamp()/uuid() 는 plan 마다 값이 바뀌어 '
                 '모든 리소스를 변경 대상으로 만듭니다'
                 % os.path.relpath(path, ROOT))


# ═════════════════════════════════════════════════════════ 결과

print('-' * 66)
if warnings:
    print(' 경고 %d건' % len(warnings))
    for check, message in warnings:
        print('   ⚠ [%s] %s' % (check, message))
    print()

if failures:
    print(' 실패 %d건' % len(failures))
    for check, message in failures:
        print('   ✗ [%s] %s' % (check, message))
    print()
    print(' 결과: 실패 — 위 항목을 수정한 뒤 terraform plan 을 실행하세요.')
    sys.exit(1)

print(' 결과: 통과 — 정적 검증 7항목을 모두 만족합니다.')
print()
print(' ⚠️ 이 검증은 «문법과 규칙»만 봅니다.')
print('    Azure 리소스 제약(SKU 조합·이름 중복 등)은')
print('    terraform validate 와 terraform plan 이 확인합니다.')
sys.exit(0)
