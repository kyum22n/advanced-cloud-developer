/**
 * 나만의 업무 앱 — HTML5 + 바닐라 JavaScript 프런트엔드.
 *
 * 설계 근거
 *   - API 계약: 개발/공통/openapi.yaml
 *   - E2E 선택자: data-testid 를 고정한다 (설계/공통/06 §E-A-01~04)
 *
 * 프레임워크를 쓰지 않는 이유
 *   «화면이 어떻게 갱신되는가»를 직접 보이게 하려는 것입니다.
 *   같은 화면의 Vue 구현과 비교하면 프레임워크가 무엇을 대신해 주는지 드러납니다.
 */
(function () {
  "use strict";

  /** API 기준 주소. 같은 오리진에서 서빙되면 비워 둔다. */
  var BASE = window.API_BASE || "";

  function $(selector) {
    return document.querySelector(selector);
  }

  function testid(name) {
    return document.querySelector('[data-testid="' + name + '"]');
  }

  function showError(message) {
    var box = testid("error-message");
    if (!message) {
      box.hidden = true;
      box.textContent = "";
      return;
    }
    box.hidden = false;
    box.textContent = message;
  }

  function formatAmount(value) {
    var n = Number(value);
    return Number.isFinite(n) ? n.toLocaleString("ko-KR") : String(value);
  }

  async function getJson(path) {
    var res = await fetch(BASE + path, { headers: { Accept: "application/json" } });
    var body = await res.json().catch(function () {
      return {};
    });
    if (!res.ok) {
      throw new Error(body.error || "요청이 실패했습니다 (HTTP " + res.status + ")");
    }
    return body;
  }

  async function loadVersion() {
    try {
      var v = await getJson("/version");
      testid("env-badge").textContent = v.env || "-";
      testid("version-badge").textContent = v.version || "-";
    } catch (e) {
      testid("env-badge").textContent = "?";
    }
  }

  async function loadItems() {
    var data = await getJson("/api/items");
    var tbody = testid("item-tbody");
    tbody.textContent = "";
    testid("empty-message").hidden = data.count > 0;
    (data.items || []).forEach(function (item) {
      var tr = document.createElement("tr");
      tr.setAttribute("data-testid", "item-row");
      [item.id, item.title, formatAmount(item.amount), item.createdAt].forEach(function (cell) {
        var td = document.createElement("td");
        // textContent 를 쓴다 — innerHTML 은 입력값이 마크업으로 해석되어 XSS 통로가 된다
        td.textContent = String(cell);
        tr.appendChild(td);
      });
      tbody.appendChild(tr);
    });
  }

  async function loadSummary() {
    var data = await getJson("/api/summary");
    var tbody = testid("summary-tbody");
    tbody.textContent = "";
    (data.weeks || []).forEach(function (week) {
      var tr = document.createElement("tr");
      tr.setAttribute("data-testid", "summary-row");
      [week.week, week.count, formatAmount(week.amount)].forEach(function (cell) {
        var td = document.createElement("td");
        td.textContent = String(cell);
        tr.appendChild(td);
      });
      tbody.appendChild(tr);
    });
  }

  async function refresh() {
    await Promise.all([loadItems(), loadSummary()]);
  }

  async function onSubmit(event) {
    event.preventDefault();
    showError("");
    var title = $("#title").value;
    var amount = $("#amount").value;
    var res = await fetch(BASE + "/api/items", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title: title, amount: amount }),
    });
    var body = await res.json().catch(function () {
      return {};
    });
    if (res.status !== 201) {
      showError(body.error || "등록에 실패했습니다.");
      return;
    }
    $("#title").value = "";
    $("#amount").value = "0";
    await refresh();
  }

  document.addEventListener("DOMContentLoaded", function () {
    testid("create-form").addEventListener("submit", onSubmit);
    loadVersion();
    refresh().catch(function (e) {
      showError(e.message);
    });
  });
})();
