"use strict";
/**
 * 점수 · 레벨 · 중력 간격 규칙 — 순수 함수 모듈 (I/O 없음).
 * 설계 근거: 설계/공통/02_도메인·클래스설계서.md §3-2(ScoreRule) · §3-4(상수)
 *            설계/공통/01_기능명세서.md AC-B-04·05
 */
(function (exportsObj) {
  var LINE_POINTS = { 0: 0, 1: 100, 2: 300, 3: 500, 4: 800 };
  var LINES_PER_LEVEL = 10;
  var BASE_GRAVITY_MS = 800;
  var GRAVITY_STEP_MS = 70;
  var MIN_GRAVITY_MS = 80;

  /** 제거한 줄 수와 현재 레벨로 획득 점수를 계산한다. */
  function pointsFor(lines, level) {
    var base = LINE_POINTS[lines] || 0;
    var lv = Math.max(1, level | 0);
    return base * lv;
  }

  /** 누적 제거 줄 수로 현재 레벨을 계산한다(10줄마다 레벨업). */
  function levelFor(totalLines) {
    return Math.floor(Math.max(0, totalLines) / LINES_PER_LEVEL) + 1;
  }

  /** 레벨에 따른 중력(자동 하강) 간격(ms). 레벨이 오를수록 짧아지되 최소값 아래로는 내려가지 않는다. */
  function gravityInterval(level) {
    var lv = Math.max(1, level | 0);
    return Math.max(MIN_GRAVITY_MS, BASE_GRAVITY_MS - (lv - 1) * GRAVITY_STEP_MS);
  }

  exportsObj.pointsFor = pointsFor;
  exportsObj.levelFor = levelFor;
  exportsObj.gravityInterval = gravityInterval;
})(
  typeof module !== "undefined" && module.exports
    ? module.exports
    : (window.TetrisScoreRule = {})
);
