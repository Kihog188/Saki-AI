// Wires the page together: history, character, chat connection, panels and status line.

import { api } from "./api.js";
import { Character } from "./character.js";
import { ChatController, ChatView, Connection } from "./chat.js";
import { setupMemories, setupSettings } from "./panels.js";

const $ = (id) => document.getElementById(id);

const view = new ChatView($("messages"));
const character = new Character($("char-img"));
const input = $("input");
const sendButton = $("send");
const stopButton = $("stop");
const statusLine = $("status");

const status = { connected: false, everConnected: false, turn: null, llmDown: false };

function renderStatus() {
  let text;
  if (!status.connected) text = status.everConnected ? "Mất kết nối với Saki" : "Đang kết nối...";
  else if (status.turn === "searching") text = "Đang tìm kiếm...";
  else if (status.turn === "thinking") text = "Saki đang suy nghĩ...";
  else if (status.turn === "answering") text = "Saki đang trả lời...";
  else if (status.llmDown) text = "Chưa kết nối được với mô hình";
  else text = "Sẵn sàng";
  statusLine.textContent = text;
  sendButton.disabled = !chat.canSend || chat.busy;
  stopButton.hidden = !chat.busy;
}

async function checkHealth() {
  try {
    const health = await api.health();
    status.llmDown = health.llm.reachable === false;
  } catch {
    // the connection status already covers a dead backend
  }
  renderStatus();
}

const memories = setupMemories($("memories-dialog"));

const connection = new Connection(`ws://${location.host}/ws`, {
  onOpen() {
    status.connected = status.everConnected = true;
    renderStatus();
    checkHealth();
  },
  onClose() {
    status.connected = false;
    chat.disconnected();
  },
  onEvent: (event) => chat.handle(event),
});

const chat = new ChatController({
  view,
  character,
  connection,
  onChange(state) {
    status.turn = state;
    renderStatus();
  },
  onSystemReply: () => memories.refresh(),
  onError: checkHealth,
});

const settings = setupSettings($("settings-dialog"), {
  onSaved(saved, changes) {
    if ("character_pack" in changes) character.usePack(saved.character_pack);
  },
  onHistoryCleared: () => view.clear(),
});

$("open-memories").addEventListener("click", memories.open);
$("open-settings").addEventListener("click", settings.open);

$("composer").addEventListener("submit", (e) => {
  e.preventDefault();
  if (chat.busy) return; // the send button is disabled during a turn; Enter can still supersede
  if (chat.submit(input.value)) input.value = "";
});

input.addEventListener("keydown", (e) => {
  if (e.key !== "Enter" || e.shiftKey || e.isComposing) return;
  e.preventDefault();
  if (chat.submit(input.value)) input.value = "";
});

stopButton.addEventListener("click", () => chat.stop());

async function loadHistory() {
  const { messages } = await api.history(50);
  let lastEmotion = null;
  for (const m of messages) {
    if (m.role === "user") view.addUser(m.content);
    else if (m.role === "assistant") {
      view.addSaki(m.content);
      lastEmotion = m.emotion || "neutral";
    }
  }
  view.scrollToEnd();
  if (lastEmotion) character.settle(lastEmotion);
}

async function start() {
  renderStatus();
  try {
    const saved = await api.settings();
    await character.usePack(saved.character_pack);
  } catch {
    await character.usePack("default").catch(() => {});
  }
  try {
    await loadHistory();
  } catch (err) {
    view.addError(`Không tải được lịch sử: ${err.message}`);
  }
  connection.connect();
}

start();
