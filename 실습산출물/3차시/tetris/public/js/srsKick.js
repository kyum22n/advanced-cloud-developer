"use strict";
/**
 * SRS 스타일 월킥 오프셋 — 순수 함수 모듈 (I/O 없음, 상태 변경 없음).
 * 설계 근거: 설계/공통/02_도메인·클래스설계서.md §3-2(SrsKick)
 *            설계/공통/01_기능명세서.md FR-B-03 · AC-B-03
 *
 * 좌표계: x=열(오른쪽 +) · y=행(아래쪽 +). 회전 상태: 0(스폰)→1(R)→2(180)→3(L)→0.
 */
(function (exportsObj) {
  // JLSTZ 공용 킥 테이블. 키는 "from>to".
  var JLSTZ_KICKS = {
    "0>1": [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
    "1>0": [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
    "1>2": [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
    "2>1": [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
    "2>3": [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
    "3>2": [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
    "3>0": [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
    "0>3": [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
  };

  // I 블록 전용 킥 테이블(더 넓은 오프셋이 필요).
  var I_KICKS = {
    "0>1": [[0, 0], [-2, 0], [1, 0], [-2, 1], [1, -2]],
    "1>0": [[0, 0], [2, 0], [-1, 0], [2, -1], [-1, 2]],
    "1>2": [[0, 0], [-1, 0], [2, 0], [-1, -2], [2, 1]],
    "2>1": [[0, 0], [1, 0], [-2, 0], [1, 2], [-2, -1]],
    "2>3": [[0, 0], [2, 0], [-1, 0], [2, -1], [-1, 2]],
    "3>2": [[0, 0], [-2, 0], [1, 0], [-2, 1], [1, -2]],
    "3>0": [[0, 0], [1, 0], [-2, 0], [1, 2], [-2, -1]],
    "0>3": [[0, 0], [-1, 0], [2, 0], [-1, -2], [2, 1]],
  };

  /** 회전 전이(from→to)에 시도할 오프셋 목록을 순서대로 반환한다. */
  function kickOffsets(type, from, to) {
    if (type === "O") return [[0, 0]];
    var table = type === "I" ? I_KICKS : JLSTZ_KICKS;
    var key = from + ">" + to;
    return table[key] || [[0, 0]];
  }

  /**
   * 충돌 판정 함수(isCollisionAt)를 주입받아 킥을 순서대로 시도한다.
   * isCollisionAt(rotatedPiece, x, y) => boolean
   * 성공하면 {x,y} 오프셋 좌표를, 실패하면 null 을 반환한다(순수 — 입력을 변경하지 않는다).
   */
  function tryRotate(isCollisionAt, piece, rotatedPiece) {
    var offsets = kickOffsets(piece.type, piece.rotation, rotatedPiece.rotation);
    for (var i = 0; i < offsets.length; i++) {
      var nx = piece.x + offsets[i][0];
      var ny = piece.y + offsets[i][1];
      if (!isCollisionAt(rotatedPiece, nx, ny)) return { x: nx, y: ny };
    }
    return null;
  }

  exportsObj.kickOffsets = kickOffsets;
  exportsObj.tryRotate = tryRotate;
})(
  typeof module !== "undefined" && module.exports
    ? module.exports
    : (window.TetrisSrsKick = {})
);
