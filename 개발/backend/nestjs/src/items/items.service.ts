import { BadRequestException, Injectable } from '@nestjs/common';
import { DbService } from '../db/db.service';
import { dedupeById, ItemLike, summarizeByWeek, WeekSummary } from '../common/summary';

const MAX_ROWS = 200;

export interface ItemRow extends ItemLike {
  createdAt: string;
}

/** 항목 유스케이스. 컨트롤러는 얇게 두고 규칙은 여기 모은다. */
@Injectable()
export class ItemsService {
  constructor(private readonly db: DbService) {}

  async list(limit: number): Promise<ItemRow[]> {
    const bounded = Math.min(Math.max(Number(limit) || MAX_ROWS, 1), MAX_ROWS);
    const r = await this.db.raw.query(
      'SELECT id, title, amount, created_at FROM items ORDER BY id DESC LIMIT $1',
      [bounded],
    );
    return dedupeById(r.rows.map(ItemsService.toRow));
  }

  async create(title: unknown, amount: unknown, actor: string): Promise<ItemRow> {
    const trimmed = typeof title === 'string' ? title.trim() : '';
    if (trimmed === '') {
      throw new BadRequestException({ error: 'title 은 필수이며 빈 문자열일 수 없습니다.' });
    }
    const value = amount === undefined || amount === null || amount === '' ? 0 : Number(amount);
    if (Number.isNaN(value)) {
      throw new BadRequestException({ error: 'amount 는 숫자여야 합니다.' });
    }
    const r = await this.db.raw.query(
      'INSERT INTO items (title, amount) VALUES ($1, $2) RETURNING id, title, amount, created_at',
      [trimmed, value],
    );
    const saved = ItemsService.toRow(r.rows[0]);
    await this.db.raw.query(
      'INSERT INTO audit_log (actor, action, target) VALUES ($1, $2, $3)',
      [actor || 'anonymous', 'create', `item:${saved.id}`],
    );
    return saved;
  }

  async summary(): Promise<WeekSummary[]> {
    const r = await this.db.raw.query('SELECT id, title, amount, created_at FROM items ORDER BY id ASC');
    return summarizeByWeek(r.rows.map(ItemsService.toRow));
  }

  private static toRow(row: Record<string, unknown>): ItemRow {
    return {
      id: Number(row.id),
      title: String(row.title),
      amount: Number(row.amount),
      createdAt: new Date(row.created_at as string).toISOString(),
    };
  }
}
