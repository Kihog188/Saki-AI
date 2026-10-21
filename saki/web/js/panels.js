// Memories drawer and settings dialog (REST only).

import { api } from "./api.js";

function setupDialog(dialog, onOpen) {
  dialog.querySelector("[data-close]").addEventListener("click", () => dialog.close());
  return () => {
    dialog.showModal();
    onOpen();
  };
}

function showMessage(el, text, isError = false) {
  el.textContent = text;
  el.classList.toggle("error", isError);
}

export function setupMemories(dialog) {
  const form = dialog.querySelector("#memory-form");
  const input = dialog.querySelector("#memory-input");
  const list = dialog.querySelector("#memory-list");
  const msg = dialog.querySelector("#memory-msg");

  async function refresh() {
    let memories;
    try {
      ({ memories } = await api.memories());
    } catch (err) {
      showMessage(msg, err.message, true);
      return;
    }
    list.replaceChildren(
      ...memories.map((m) => {
        const li = document.createElement("li");
        const text = document.createElement("span");
        const id = document.createElement("span");
        id.className = "id";
        id.textContent = `#${m.id}`;
        text.append(id, document.createTextNode(m.text));
        const del = document.createElement("button");
        del.type = "button";
        del.className = "link";
        del.textContent = "Xóa";
        del.addEventListener("click", () => remove(m));
        li.append(text, del);
        return li;
      }),
    );
    if (memories.length === 0) {
      const li = document.createElement("li");
      li.className = "note";
      li.textContent = "Chưa có ghi nhớ nào.";
      list.append(li);
    }
  }

  async function remove(memory) {
    if (!confirm(`Xóa ghi nhớ này?\n\n${memory.text}`)) return;
    try {
      await api.deleteMemory(memory.id);
      showMessage(msg, "Đã xóa.");
    } catch (err) {
      showMessage(msg, err.message, true);
    }
    refresh();
  }

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    try {
      const memory = await api.addMemory(input.value);
      showMessage(msg, `Đã nhớ: ${memory.text}`);
      input.value = "";
    } catch (err) {
      showMessage(msg, err.message, true);
    }
    refresh();
  });

  const open = setupDialog(dialog, () => {
    showMessage(msg, "");
    refresh();
  });
  return { open, refresh };
}

export function setupSettings(dialog, { onSaved, onHistoryCleared }) {
  const form = dialog.querySelector("#settings-form");
  const select = form.elements.character_pack;
  const msg = dialog.querySelector("#settings-msg");
  const packNote = dialog.querySelector("#pack-note");
  const FIELDS = ["self_name", "user_name", "model", "character_pack"];
  let loaded = null;

  async function load() {
    showMessage(msg, "");
    packNote.textContent = "";
    let settings, packs;
    try {
      [settings, { packs }] = await Promise.all([api.settings(), api.characters()]);
    } catch (err) {
      showMessage(msg, err.message, true);
      return;
    }
    select.replaceChildren(
      ...packs
        .filter((p) => p.valid)
        .map((p) => {
          const option = document.createElement("option");
          option.value = p.id;
          option.textContent = p.author ? `${p.name} (${p.author})` : p.name;
          return option;
        }),
    );
    const invalid = packs.filter((p) => !p.valid);
    if (invalid.length) {
      packNote.textContent =
        "Gói không hợp lệ (không dùng được): " + invalid.map((p) => `${p.id}: ${p.error}`).join("; ");
    }
    for (const name of FIELDS) form.elements[name].value = settings[name];
    if (select.value !== settings.character_pack) select.value = "default";
    loaded = settings;
  }

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    if (!loaded) return;
    const changes = {};
    for (const name of FIELDS) {
      const value = form.elements[name].value.trim();
      if (value !== loaded[name]) changes[name] = value;
    }
    if (Object.keys(changes).length === 0) {
      showMessage(msg, "Không có gì thay đổi.");
      return;
    }
    try {
      const saved = await api.saveSettings(changes);
      loaded = saved;
      showMessage(
        msg,
        saved.restart_required ? "Đã lưu. Hãy khởi động lại Saki để áp dụng." : "Đã lưu.",
      );
      onSaved(saved, changes);
    } catch (err) {
      showMessage(msg, err.message, true);
    }
  });

  dialog.querySelector("#clear-history").addEventListener("click", async () => {
    if (!confirm("Xóa toàn bộ lịch sử trò chuyện? Ghi nhớ vẫn được giữ.")) return;
    try {
      await api.clearHistory();
      showMessage(msg, "Đã xóa lịch sử trò chuyện.");
      onHistoryCleared();
    } catch (err) {
      showMessage(msg, err.message, true);
    }
  });

  return { open: setupDialog(dialog, load) };
}
