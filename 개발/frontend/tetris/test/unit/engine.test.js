"use strict";
/**
 * 단위 테스트 — 설계/공통/06 §2-2 의 U-B-01~10 에 대응한다.
 * 순수 로직(engine.js · scoreRule.js)만 검증한다 — 브라우저·DOM 불필요.
 */
const test = require("node:test");
const assert = require("node:assert");

const { GameEngine, Board, Piece, GameState } = require("../../public/js/engine.js");
const { levelFor, gravityInterval } = require("../../public/js/scoreRule.js");

// 항상 "I"(인덱스 0)를 선택하는 결정적 rng — 조각 종류는 각 테스트에서 직접 지정한다.
const rng0 = () => 0;

test("U-B-01 벽 충돌 — 좌측 벽에 인접한 블록은 이동하지 않는다", () => {
  const engine = new GameEngine({ rng: rng0 });
  engine.current = new Piece("I", 0, 0, 5); // 행 = y+1 = 6, 열 0~3
  const before = { x: engine.current.x, y: engine.current.y };
  const moved = engine.moveLeft();
  assert.strictEqual(moved, false);
  assert.strictEqual(engine.current.x, before.x);
  assert.strictEqual(engine.current.y, before.y);
});

test("U-B-02 바닥·블록 충돌 후 고정 — tick() 이 고정하고 다음 블록을 생성한다", () => {
  const engine = new GameEngine({ rng: rng0 });
  engine.current = new Piece("I", 0, 3, 5); // I 는 행 y+1=6 에만 칸을 가진다
  // 한 칸 아래(7행)를 막아 충돌을 만든다 — 마지막 열은 비워 두어 «완성된 줄»로 오인해 자동 클리어되지 않게 한다
  for (let x = 0; x < engine.board.width - 1; x++) engine.board.grid[7][x] = "X";
  const before = engine.current;
  engine.tick();
  assert.notStrictEqual(engine.current, before, "새 블록이 생성되어야 한다");
  assert.ok(engine.board.grid[6].some(Boolean), "이전 블록이 6행에 고정되어 있어야 한다");
});

test("U-B-03 회전 + 월킥 — I 블록이 벽에 붙어 회전 불가 위치에서 오프셋 보정 후 회전 성공", () => {
  const engine = new GameEngine({ rng: rng0 });
  // 세로(rotation=1, 점유 열 x+2=9, 유효)로 우측 벽에 붙여 둔다.
  // 가로(rotation=2)로 그대로 돌리면 열 7~10 이 되어 10(범위 밖)과 충돌 → 월킥 필요.
  engine.current = new Piece("I", 1, 7, 5);
  const rotated = engine.rotate(1);
  assert.strictEqual(rotated, true, "월킥으로 회전에 성공해야 한다");
  assert.strictEqual(engine.current.rotation, 2);
  for (const [cx] of engine.current.cells()) {
    assert.ok(cx >= 0 && cx < engine.board.width, `열 ${cx} 이 보드 범위 안이어야 한다`);
  }
});

test("U-B-04 1줄 클리어·점수 — 한 줄이 가득 차면 제거되고 100×레벨 점수가 오른다", () => {
  const engine = new GameEngine({ rng: rng0 });
  const w = engine.board.width;
  const h = engine.board.height;
  // 바닥 행의 마지막 두 칸(w-2, w-1)만 비워 둔다.
  for (let x = 0; x < w - 2; x++) engine.board.grid[h - 1][x] = "X";
  // O 는 rotation0 에서 열 x+1, x+2 를 차지한다 → x=w-3 이면 열 w-2, w-1 에 정확히 들어맞는다.
  engine.current = new Piece("O", 0, w - 3, 0);
  const before = engine.score;
  engine.hardDrop();
  assert.strictEqual(engine.score - before, 100 * 1, "1줄 클리어 점수는 100×레벨 이어야 한다");
});

test("U-B-05 4줄 클리어(테트리스) — 하드 드롭으로 4줄을 동시에 지우면 800×레벨 점수가 오른다", () => {
  const engine = new GameEngine({ rng: rng0 });
  const w = engine.board.width;
  const h = engine.board.height;
  // 마지막 열(w-1)만 비우고 바닥 4개 행을 채운다.
  for (let y = h - 4; y < h; y++) {
    for (let x = 0; x < w - 1; x++) engine.board.grid[y][x] = "X";
  }
  // I 세로(rotation1)는 열 x+2 를 차지한다 → x=w-3 이면 빈 열(w-1)에 정확히 들어맞는다.
  engine.current = new Piece("I", 1, w - 3, 0);
  const before = engine.score;
  engine.hardDrop();
  assert.strictEqual(engine.score - before, 800 * 1, "4줄 동시 클리어 점수는 800×레벨 이어야 한다");
});

test("U-B-06 게임오버 판정 — 스폰 위치가 막혀 있으면 GAMEOVER 로 전환한다", () => {
  const engine = new GameEngine({ rng: rng0 });
  // 모든 조각의 rotation0 은 0·1 행 안에서만 칸을 가지므로, 두 행을 모두 막으면 어떤 조각이든 충돌한다.
  for (let x = 0; x < engine.board.width; x++) {
    engine.board.grid[0][x] = "X";
    engine.board.grid[1][x] = "X";
  }
  engine.spawnNext();
  assert.strictEqual(engine.state, GameState.GAMEOVER);
});

test("U-B-07 게임오버 후 입력 무시 — 보드가 바뀌지 않는다", () => {
  const engine = new GameEngine({ rng: rng0 });
  engine.state = GameState.GAMEOVER;
  const before = engine.board.grid.map((r) => r.slice());
  engine.moveLeft();
  engine.tick();
  assert.deepStrictEqual(engine.board.grid, before);
});

test("U-B-08 일시정지 중 중력 무시 — tick() 이 블록을 하강시키지 않는다", () => {
  const engine = new GameEngine({ rng: rng0 });
  engine.state = GameState.PAUSED;
  const y0 = engine.current.y;
  engine.tick();
  assert.strictEqual(engine.current.y, y0);
});

test("U-B-09 레벨·중력 간격 — 누적 10줄이면 레벨 2, 간격이 줄어든다", () => {
  assert.strictEqual(levelFor(10), 2);
  assert.ok(gravityInterval(2) < gravityInterval(1), "레벨이 오르면 간격이 짧아져야 한다");
});

test("U-B-10 라인 인덱스 무결성 — 중간 줄만 가득 차면 위쪽 줄만 내려오고 구멍이 없다", () => {
  const board = new Board(4, 5);
  board.grid[1][0] = "A"; // 지워질 줄 위
  board.grid[2] = ["X", "X", "X", "X"]; // 가득 참 → 제거 대상
  board.grid[3][1] = "B"; // 지워질 줄 아래 — 영향 없어야 함

  const cleared = board.clearLines();

  assert.strictEqual(cleared, 1);
  assert.deepStrictEqual(board.grid[0], [0, 0, 0, 0], "맨 위에 새 빈 줄이 생겨야 한다");
  assert.strictEqual(board.grid[2][0], "A", "위쪽 줄이 한 칸 내려와야 한다");
  assert.strictEqual(board.grid[3][1], "B", "아래쪽 줄은 그대로여야 한다");
});
