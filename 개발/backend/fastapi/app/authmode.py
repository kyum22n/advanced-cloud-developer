"""DB 인증 방식을 «환경이 스스로» 고르게 하는 순수 로직.

설계 근거: 설계/공통/07_아이덴티티·시크릿_설계서.md §5
외부 의존이 없으므로 단위 테스트로 고정한다(U-A-07~10).
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Literal, TypedDict

AuthModeName = Literal["entra", "password"]

WORKLOAD_IDENTITY_VARS = ("AZURE_CLIENT_ID", "AZURE_TENANT_ID", "AZURE_FEDERATED_TOKEN_FILE")


class AuthInfo(TypedDict):
    """진단용 요약. 자격 증명 «값»은 어떤 경우에도 담지 않는다."""

    mode: AuthModeName
    user: str
    workloadIdentity: bool
    passwordConfigured: bool


def _not_blank(value: str | None) -> bool:
    return isinstance(value, str) and value.strip() != ""


def workload_identity_available(env: Mapping[str, str]) -> bool:
    """워크로드 ID 환경 변수 3종이 모두 있어야 사용 가능으로 본다."""
    return all(_not_blank(env.get(name)) for name in WORKLOAD_IDENTITY_VARS)


def resolve_auth_mode(env: Mapping[str, str]) -> AuthModeName:
    """명시 지정이 자동 선택보다 우선한다. 알 수 없는 값은 자동 선택으로 되돌아간다."""
    explicit = str(env.get("DB_AUTH_MODE", "")).lower()
    if explicit in ("entra", "password"):
        return explicit  # type: ignore[return-value]
    if workload_identity_available(env) and not _not_blank(env.get("DB_PASSWORD")):
        return "entra"
    return "password"


def auth_info(env: Mapping[str, str]) -> AuthInfo:
    """인증 «방식»만 노출한다."""
    return AuthInfo(
        mode=resolve_auth_mode(env),
        user=env.get("DB_USER", "appuser"),
        workloadIdentity=workload_identity_available(env),
        passwordConfigured=_not_blank(env.get("DB_PASSWORD")),
    )
