import { Body, Controller, Get, Headers, HttpCode, Post, Query } from '@nestjs/common';
import { ItemsService } from './items.service';

/** 항목 API. 계약은 개발/공통/openapi.yaml 을 따른다. */
@Controller('api')
export class ItemsController {
  constructor(private readonly items: ItemsService) {}

  @Get('items')
  async list(@Query('limit') limit?: string): Promise<{ count: number; items: unknown[] }> {
    const rows = await this.items.list(Number(limit ?? 200));
    return { count: rows.length, items: rows };
  }

  @Post('items')
  @HttpCode(201)
  async create(
    @Body() body: Record<string, unknown> | undefined,
    @Headers('x-user') actor?: string,
  ): Promise<unknown> {
    const payload = body ?? {};
    return this.items.create(payload.title, payload.amount, actor ?? 'anonymous');
  }

  @Get('summary')
  async summary(): Promise<{ weeks: unknown[] }> {
    return { weeks: await this.items.summary() };
  }
}
