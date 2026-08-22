import { Controller, Get, HttpStatus, Res } from '@nestjs/common';
import type { Response } from 'express';
import { DbService } from '../db/db.service';
import { authInfo } from '../common/authmode';

/** 프로브·버전 엔드포인트. */
@Controller()
export class HealthController {
  constructor(private readonly db: DbService) {}

  /**
   * 생존 프로브. 의존성을 확인하지 않는다 — 여기서 DB 를 보면
   * DB 가 잠시 끊겼을 때 파드가 재시작되어 상황이 악화된다.
   */
  @Get('healthz')
  healthz(): { status: string; env: string } {
    return { status: 'ok', env: process.env.APP_ENV ?? 'dev' };
  }

  /** 준비 프로브. DB 연결을 실제로 확인한다. */
  @Get('readyz')
  async readyz(@Res() res: Response): Promise<void> {
    try {
      const ok = await this.db.ping();
      if (ok) {
        res.status(HttpStatus.OK).json({ status: 'ready' });
        return;
      }
    } catch {
      // 아래 공통 처리로 떨어뜨린다
    }
    res.status(HttpStatus.SERVICE_UNAVAILABLE).json({ status: 'not-ready', reason: 'database' });
  }

  /** 배포 버전·환경·인증 방식. 자격 증명 값은 담지 않는다. */
  @Get('version')
  version(): Record<string, unknown> {
    return {
      version: process.env.APP_VERSION ?? '0.0.0',
      env: process.env.APP_ENV ?? 'dev',
      auth: authInfo(process.env),
    };
  }
}
