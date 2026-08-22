"""단위 테스트 — 설계/공통/06 의 U-A-07~10 에 대응한다."""

from __future__ import annotations

import json

from app.authmode import auth_info, resolve_auth_mode, workload_identity_available

WI = {
    "AZURE_CLIENT_ID": "cid",
    "AZURE_TENANT_ID": "tid",
    "AZURE_FEDERATED_TOKEN_FILE": "/var/run/secrets/azure/tokens/azure-identity-token",
}


def test_u_a_07_detect() -> None:
    """워크로드 ID 는 3종이 모두 있어야 사용 가능."""
    assert workload_identity_available(WI) is True
    assert workload_identity_available({**WI, "AZURE_TENANT_ID": ""}) is False
    assert workload_identity_available({}) is False


def test_u_a_08_auto_select() -> None:
    """비밀번호가 없고 워크로드 ID 가 있으면 토큰 인증."""
    assert resolve_auth_mode(WI) == "entra"
    assert resolve_auth_mode({**WI, "DB_PASSWORD": "p"}) == "password"
    assert resolve_auth_mode({}) == "password"


def test_u_a_09_explicit_wins() -> None:
    """명시 지정이 자동 선택보다 우선."""
    assert resolve_auth_mode({**WI, "DB_PASSWORD": "p", "DB_AUTH_MODE": "ENTRA"}) == "entra"
    assert resolve_auth_mode({**WI, "DB_AUTH_MODE": "kerberos"}) == "entra"


def test_u_a_10_no_secret_leak() -> None:
    """진단 정보에 비밀값이 담기지 않는다."""
    info = auth_info({**WI, "DB_PASSWORD": "super-secret", "DB_USER": "id-myapp-prd"})
    assert info["mode"] == "password"
    assert info["passwordConfigured"] is True
    assert "super-secret" not in json.dumps(info)
    assert "password" not in info
