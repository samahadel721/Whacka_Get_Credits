/**
 * __PROJECT_NAME__ — منطق الصفحة.
 * localStorage هنا للتجربة المحلية فقط؛ البيانات لا تُرسل لأي خادم.
 */
const KEY_NOTES = "__PROJECT_NAME__:notes";
const KEY_CLICKS = "__PROJECT_NAME__:clicks";

const $ = (sel) => document.querySelector(sel);
const read = (key, fallback) => {
  try { return JSON.parse(localStorage.getItem(key)) ?? fallback; } catch { return fallback; }
};
const write = (key, value) => {
  try { localStorage.setItem(key, JSON.stringify(value)); } catch (e) { console.warn("تخزين ممتلئ/محظور", e); }
};

let notes = read(KEY_NOTES, []);
let clicks = read(KEY_CLICKS, 0);

function render() {
  $("#t-clicks").textContent = String(clicks);
  $("#t-store").textContent = String(notes.length);
  $("#t-online").textContent = navigator.onLine ? "نعم" : "لا";
  const list = $("#notes-list");
  list.textContent = "";
  if (!notes.length) {
    const li = document.createElement("li");
    li.textContent = "لا ملاحظات بعد.";
    list.append(li);
    return;
  }
  for (const [i, text] of notes.entries()) {
    const li = document.createElement("li");
    const span = document.createElement("span");
    span.textContent = text;                    // textContent يمنع HTML injection
    const del = document.createElement("button");
    del.className = "link";
    del.textContent = "حذف";
    del.onclick = () => { notes.splice(i, 1); write(KEY_NOTES, notes); render(); };
    li.append(span, del);
    list.append(li);
  }
}

$("#ping").addEventListener("click", async () => {
  const t0 = performance.now();
  try {
    const r = await fetch(`${location.pathname}?_=${Date.now()}`, { method: "HEAD", cache: "no-store" });
    $("#ping-state").textContent = `${r.status} · ${(performance.now() - t0).toFixed(0)}ms`;
  } catch (e) {
    $("#ping-state").textContent = "فشل الاتصال";
  }
  clicks += 1; write(KEY_CLICKS, clicks); render();
});

$("#note-form").addEventListener("submit", (ev) => {
  ev.preventDefault();
  const input = $("#note-input");
  const text = input.value.trim().slice(0, 140);
  if (!text) return;
  notes.unshift(text);
  notes = notes.slice(0, 100);                   // سقف حتى لا يمتلئ التخزين
  write(KEY_NOTES, notes);
  input.value = "";
  render();
});

addEventListener("online", render);
addEventListener("offline", render);
render();
