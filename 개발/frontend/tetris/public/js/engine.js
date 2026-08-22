"use strict";
/**
 * 웹 테트리스 게임 엔진 — 순수 로직 (DOM · 렌더 · 입력에 의존하지 않는다).
 * 설계 근거: 설계/공통/02_도메인·클래스설계서.md §3 (GameEngine · Board · Piece · GameState)
 *            설계/공통/01_기능명세서.md FR-B-01~12 · AC-B-01~08
 *
 * NFR-B-02: 이 파일은 브라우저 없이(Node 의 node:test 로) 단위 테스트가 가능해야 한다.
 */
(function (exportsObj, deps) {
  var scoreRule = deps.scoreRule;
  var srsKick = deps.srsKick;

  var GameState = { READY: "READY", PLAYING: "PLAYING", PAUSED: "PAUSED", GAMEOVER: "GAMEOVER" };

  // 표준 SRS 스폰 방향 기준 4x4 바운딩 박스 좌표. rotation: 0(스폰)·1(R)·2(180)·3(L).
  var TETROMINOES = {
    I: [
      [[0, 1], [1, 1], [2, 1], [3, 1]],
      [[2, 0], [2, 1], [2, 2], [2, 3]],
      [[0, 2], [1, 2], [2, 2], [3, 2]],
      [[1, 0], [1, 1], [1, 2], [1, 3]],
    ],
    O: [
      [[1, 0], [2, 0], [1, 1], [2, 1]],
      [[1, 0], [2, 0], [1, 1], [2, 1]],
      [[1, 0], [2, 0], [1, 1], [2, 1]],
      [[1, 0], [2, 0], [1, 1], [2, 1]],
    ],
    T: [
      [[1, 0], [0, 1], [1, 1], [2, 1]],
      [[1, 0], [1, 1], [2, 1], [1, 2]],
      [[0, 1], [1, 1], [2, 1], [1, 2]],
      [[1, 0], [0, 1], [1, 1], [1, 2]],
    ],
    S: [
      [[1, 0], [2, 0], [0, 1], [1, 1]],
      [[1, 0], [1, 1], [2, 1], [2, 2]],
      [[1, 1], [2, 1], [0, 2], [1, 2]],
      [[0, 0], [0, 1], [1, 1], [1, 2]],
    ],
    Z: [
      [[0, 0], [1, 0], [1, 1], [2, 1]],
      [[2, 0], [1, 1], [2, 1], [1, 2]],
      [[0, 1], [1, 1], [1, 2], [2, 2]],
      [[1, 0], [0, 1], [1, 1], [0, 2]],
    ],
    J: [
      [[0, 0], [0, 1], [1, 1], [2, 1]],
      [[1, 0], [2, 0], [1, 1], [1, 2]],
      [[0, 1], [1, 1], [2, 1], [2, 2]],
      [[1, 0], [1, 1], [0, 2], [1, 2]],
    ],
    L: [
      [[2, 0], [0, 1], [1, 1], [2, 1]],
      [[1, 0], [1, 1], [1, 2], [2, 2]],
      [[0, 1], [1, 1], [2, 1], [0, 2]],
      [[0, 0], [1, 0], [1, 1], [1, 2]],
    ],
  };
  var PIECE_TYPES = Object.keys(TETROMINOES);

  function randomType(rng) {
    return PIECE_TYPES[Math.floor(rng() * PIECE_TYPES.length)];
  }

  // ---- Piece ----------------------------------------------------------
  function Piece(type, rotation, x, y) {
    this.type = type;
    this.rotation = ((rotation % 4) + 4) % 4;
    this.x = x;
    this.y = y;
  }
  Piece.prototype.cellsAt = function (x, y) {
    var shape = TETROMINOES[this.type][this.rotation];
    var out = [];
    for (var i = 0; i < shape.length; i++) out.push([x + shape[i][0], y + shape[i][1]]);
    return out;
  };
  Piece.prototype.cells = function () {
    return this.cellsAt(this.x, this.y);
  };
  Piece.prototype.rotated = function (dir) {
    var next = dir > 0 ? this.rotation + 1 : this.rotation + 3;
    return new Piece(this.type, next, this.x, this.y);
  };

  // ---- Board ------------------------------------------------------------
  function Board(width, height) {
    this.width = width || 10;
    // 20 가시 행 + 스폰 여유 2행 (설계/공통/02 §3-4)
    this.height = height || 22;
    this.grid = [];
    for (var y = 0; y < this.height; y++) this.grid.push(new Array(this.width).fill(0));
  }
  Board.prototype.isCollision = function (piece, x, y) {
    var cells = piece.cellsAt(x, y);
    for (var i = 0; i < cells.length; i++) {
      var cx = cells[i][0];
      var cy = cells[i][1];
      if (cx < 0 || cx >= this.width || cy >= this.height) return true;
      if (cy < 0) continue; // 스폰 여유 행 위쪽은 항상 허용
      if (this.grid[cy][cx]) return true;
    }
    return false;
  };
  Board.prototype.lock = function (piece) {
    var cells = piece.cells();
    for (var i = 0; i < cells.length; i++) {
      var cx = cells[i][0];
      var cy = cells[i][1];
      if (cx >= 0 && cx < this.width && cy >= 0 && cy < this.height) this.grid[cy][cx] = piece.type;
    }
  };
  Board.prototype.isEmpty = function (row) {
    return this.grid[row].every(function (c) {
      return !c;
    });
  };
  /** 가득 찬 줄을 제거하고 위 줄들을 아래로 내린다. 제거한 줄 수를 반환한다. */
  Board.prototype.clearLines = function () {
    var cleared = 0;
    for (var y = this.height - 1; y >= 0; y--) {
      var full = this.grid[y].every(function (c) {
        return !!c;
      });
      if (full) {
        this.grid.splice(y, 1);
        this.grid.unshift(new Array(this.width).fill(0));
        cleared++;
        y++; // 같은 인덱스를 다시 검사(내려온 줄이 또 가득 찼을 수 있음)
      }
    }
    return cleared;
  };

  // ---- GameEngine ---------------------------------------------------
  function GameEngine(opts) {
    opts = opts || {};
    this.board = new Board(opts.width, opts.height);
    this.rng = opts.rng || Math.random;
    this.score = 0;
    this.level = 1;
    this.linesCleared = 0;
    this.holdType = null;
    this.holdUsed = false;
    this.state = GameState.READY;
    this.next = randomType(this.rng);
    this.spawnNext();
  }

  /** 다음 조각을 스폰한다. 스폰 위치가 막혀 있으면 GAMEOVER 로 전환한다(FR-B-12 · AC-B-06). */
  GameEngine.prototype.spawnNext = function () {
    var type = this.next;
    this.next = randomType(this.rng);
    var piece = new Piece(type, 0, 3, 0);
    this.current = piece;
    this.holdUsed = false;
    if (this.board.isCollision(piece, piece.x, piece.y)) {
      this.state = GameState.GAMEOVER;
      return;
    }
    if (this.state !== GameState.PAUSED) this.state = GameState.PLAYING;
  };

  GameEngine.prototype._tryMove = function (dx, dy) {
    if (this.state !== GameState.PLAYING) return false; // AC-B-07·08
    var nx = this.current.x + dx;
    var ny = this.current.y + dy;
    if (this.board.isCollision(this.current, nx, ny)) return false;
    this.current.x = nx;
    this.current.y = ny;
    return true;
  };

  /** 좌측 이동. 벽·블록 충돌 시 false 를 반환하고 좌표는 그대로 둔다(AC-B-01). */
  GameEngine.prototype.moveLeft = function () {
    return this._tryMove(-1, 0);
  };
  GameEngine.prototype.moveRight = function () {
    return this._tryMove(1, 0);
  };
  GameEngine.prototype.softDrop = function () {
    return this._tryMove(0, 1);
  };

  /** SRS 회전 + 월킥(FR-B-03). 모든 오프셋이 실패하면 회전을 취소하고 false 를 반환한다. */
  GameEngine.prototype.rotate = function (dir) {
    if (this.state !== GameState.PLAYING) return false;
    var self = this;
    var rotated = this.current.rotated(dir);
    var isCollisionAt = function (piece, x, y) {
      return self.board.isCollision(piece, x, y);
    };
    var result = srsKick.tryRotate(isCollisionAt, this.current, rotated);
    if (!result) {
      // 명시된 킥 테이블로 해결되지 않으면 좁은 범위를 한 번 더 탐색한다(안전망).
      for (var ox = -2; ox <= 2 && !result; ox++) {
        for (var oy = -1; oy <= 1; oy++) {
          var nx = this.current.x + ox;
          var ny = this.current.y + oy;
          if (!isCollisionAt(rotated, nx, ny)) {
            result = { x: nx, y: ny };
            break;
          }
        }
      }
    }
    if (!result) return false;
    rotated.x = result.x;
    rotated.y = result.y;
    this.current = rotated;
    return true;
  };

  GameEngine.prototype._lockAndSpawn = function () {
    this.board.lock(this.current);
    var cleared = this.board.clearLines();
    if (cleared > 0) {
      this.score += scoreRule.pointsFor(cleared, this.level);
      this.linesCleared += cleared;
      this.level = scoreRule.levelFor(this.linesCleared);
    }
    this.spawnNext();
  };

  /** 즉시 바닥까지 내리고 고정한다(FR-B-06). 이동한 칸 수를 반환한다. */
  GameEngine.prototype.hardDrop = function () {
    if (this.state !== GameState.PLAYING) return 0;
    var dist = 0;
    while (!this.board.isCollision(this.current, this.current.x, this.current.y + 1)) {
      this.current.y += 1;
      dist += 1;
    }
    this._lockAndSpawn();
    return dist;
  };

  /** 중력 1틱. PLAYING 이 아니면 아무 일도 하지 않는다(AC-B-07·08). */
  GameEngine.prototype.tick = function () {
    if (this.state !== GameState.PLAYING) return;
    if (!this._tryMove(0, 1)) this._lockAndSpawn();
  };

  /** 현재 조각을 보관하고 교체한다(1회/블록, FR-B-10). */
  GameEngine.prototype.holdPiece = function () {
    if (this.state !== GameState.PLAYING || this.holdUsed) return false;
    var curType = this.current.type;
    if (this.holdType == null) {
      this.holdType = curType;
      this.spawnNext();
    } else {
      var swapped = this.holdType;
      this.holdType = curType;
      this.current = new Piece(swapped, 0, 3, 0);
      if (this.board.isCollision(this.current, this.current.x, this.current.y)) {
        this.state = GameState.GAMEOVER;
      }
    }
    this.holdUsed = true;
    return true;
  };

  /** 진행 ↔ 일시정지 전환(FR-B-11). */
  GameEngine.prototype.pause = function () {
    if (this.state === GameState.PLAYING) this.state = GameState.PAUSED;
    else if (this.state === GameState.PAUSED) this.state = GameState.PLAYING;
  };

  /** 처음부터 다시 시작한다(FR-B-12). */
  GameEngine.prototype.restart = function () {
    this.board = new Board(this.board.width, this.board.height);
    this.score = 0;
    this.level = 1;
    this.linesCleared = 0;
    this.holdType = null;
    this.holdUsed = false;
    this.state = GameState.READY;
    this.next = randomType(this.rng);
    this.spawnNext();
  };

  /** 렌더러가 읽을 스냅샷(읽기 전용 의도) — 이 객체를 통해서만 상태를 노출한다. */
  GameEngine.prototype.getSnapshot = function () {
    return {
      grid: this.board.grid.map(function (row) {
        return row.slice();
      }),
      current: {
        type: this.current.type,
        rotation: this.current.rotation,
        x: this.current.x,
        y: this.current.y,
        cells: this.current.cells(),
      },
      next: this.next,
      hold: this.holdType,
      score: this.score,
      level: this.level,
      linesCleared: this.linesCleared,
      state: this.state,
    };
  };

  exportsObj.GameEngine = GameEngine;
  exportsObj.Board = Board;
  exportsObj.Piece = Piece;
  exportsObj.GameState = GameState;
  exportsObj.TETROMINOES = TETROMINOES;
})(
  typeof module !== "undefined" && module.exports
    ? module.exports
    : (window.TetrisEngine = {}),
  typeof module !== "undefined" && module.exports
    ? { scoreRule: require("./scoreRule.js"), srsKick: require("./srsKick.js") }
    : { scoreRule: window.TetrisScoreRule, srsKick: window.TetrisSrsKick }
);
