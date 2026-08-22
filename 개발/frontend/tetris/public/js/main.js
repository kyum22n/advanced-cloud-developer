"use strict";
/**
 * 렌더 · 입력 계층 (DOM 의존) — 게임 규칙은 engine.js 에만 있다.
 * 설계 근거: 설계/공통/02_도메인·클래스설계서.md §3-1 (Renderer · InputHandler)
 */
(function () {
  var GameEngine = window.TetrisEngine.GameEngine;
  var gravityInterval = window.TetrisScoreRule.gravityInterval;

  var engine = new GameEngine();

  var boardCanvas = document.getElementById("board");
  var nextCanvas = document.getElementById("next");
  var holdCanvas = document.getElementById("hold");
  var ctx = boardCanvas.getContext("2d");
  var nctx = nextCanvas.getContext("2d");
  var hctx = holdCanvas.getContext("2d");

  var CELL = 30;
  var VISIBLE_ROWS = 20;
  var COLORS = {
    I: "#4dd0e1",
    O: "#ffd54f",
    T: "#ba68c8",
    S: "#81c784",
    Z: "#e57373",
    J: "#64b5f6",
    L: "#ffb74d",
  };
  var STATE_LABEL = { READY: "준비", PLAYING: "진행중", PAUSED: "일시정지", GAMEOVER: "게임오버" };

  function testid(name) {
    return document.querySelector('[data-testid="' + name + '"]');
  }

  function drawCell(context, x, y, color) {
    context.fillStyle = color;
    context.fillRect(x * CELL, y * CELL, CELL - 1, CELL - 1);
  }

  function drawPreview(context, canvas, type) {
    context.clearRect(0, 0, canvas.width, canvas.height);
    if (!type) return;
    context.fillStyle = COLORS[type] || "#888";
    context.fillRect(30, 30, 60, 60);
  }

  function render() {
    var snap = engine.getSnapshot();
    var offset = snap.grid.length - VISIBLE_ROWS; // 스폰 여유 행은 화면에 그리지 않는다

    ctx.clearRect(0, 0, boardCanvas.width, boardCanvas.height);
    for (var y = offset; y < snap.grid.length; y++) {
      for (var x = 0; x < snap.grid[y].length; x++) {
        if (snap.grid[y][x]) drawCell(ctx, x, y - offset, COLORS[snap.grid[y][x]] || "#888");
      }
    }
    snap.current.cells.forEach(function (cell) {
      var cy = cell[1] - offset;
      if (cy >= 0) drawCell(ctx, cell[0], cy, COLORS[snap.current.type]);
    });

    drawPreview(nctx, nextCanvas, snap.next);
    drawPreview(hctx, holdCanvas, snap.hold);

    testid("score").textContent = "점수: " + snap.score;
    testid("level").textContent = "레벨: " + snap.level;
    testid("state-badge").textContent = STATE_LABEL[snap.state] || snap.state;
    testid("next-label").textContent = snap.next || "-";
    testid("hold-label").textContent = snap.hold || "-";
    testid("debug-state").textContent = JSON.stringify({
      x: snap.current.x,
      y: snap.current.y,
      rotation: snap.current.rotation,
      type: snap.current.type,
      score: snap.score,
      level: snap.level,
      state: snap.state,
      next: snap.next,
      // 고정된 스택 격자 — 브라우저 자동조작(봇)이 다음 수를 계산할 수 있도록 노출한다.
      grid: snap.grid,
    });
  }

  var lastTick = performance.now();
  function loop(now) {
    var interval = gravityInterval(engine.getSnapshot().level);
    if (now - lastTick >= interval) {
      engine.tick();
      lastTick = now;
    }
    render();
    requestAnimationFrame(loop);
  }

  window.addEventListener("keydown", function (e) {
    switch (e.key) {
      case "ArrowLeft":
        engine.moveLeft();
        break;
      case "ArrowRight":
        engine.moveRight();
        break;
      case "ArrowDown":
        engine.softDrop();
        break;
      case "ArrowUp":
        engine.rotate(1);
        break;
      case " ":
        e.preventDefault();
        engine.hardDrop();
        break;
      case "c":
      case "C":
        engine.holdPiece();
        break;
      case "p":
      case "P":
        engine.pause();
        break;
      case "r":
      case "R":
        engine.restart();
        break;
      default:
        return;
    }
    render();
  });

  render();
  requestAnimationFrame(loop);
})();
