import { Module } from '@nestjs/common';
import { DbService } from './db/db.service';
import { HealthController } from './health/health.controller';
import { ItemsController } from './items/items.controller';
import { ItemsService } from './items/items.service';

@Module({
  controllers: [HealthController, ItemsController],
  providers: [DbService, ItemsService],
})
export class AppModule {}
