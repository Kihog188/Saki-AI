// Chat rendering, the WebSocket connection and the per-turn state machine.
// Model output and search titles are untrusted: they only ever go into textContent.

const RECONNECT_DELAYS = [1000, 2000, 5000, 10000];
const CANCEL_GRACE_MS = 3000;

function isHttpUrl(url) {
  try {
    const { protocol } = new URL(url);
    return protocol === "http:" || protocol === "https:";
  } catch {
    return false;
  }
}

function formatDate(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso || "");
  return m ? `${m[3]}/${m[2]}/${m[1]}` : "không rõ ngày";
}

/** Plain text with line breaks; text between ``` fences becomes a <pre> block. */
export function renderText(el, text) {
  el.replaceChildren();
  const parts = text.split("```");
  parts.forEach((part, i) => {
    if (i % 2 === 1) {
      const pre = document.createElement("pre");
      pre.textContent = part.replace(/^[\w+#.-]*\n/, "").replace(/\n$/, ""); // drop a language tag line
      el.append(pre);
      return;
    }
    // The <pre> is a block, so line breaks touching a fence would show as blank lines.
    if (i > 0) part = part.replace(/^\n/, "");
    if (i < parts.length - 1) part = part.replace(/\n$/, "");
    if (part) el.append(document.createTextNode(part));
  });
}

export class ChatView {
  constructor(list) {
    this.list = list;
  }

  clear() {
    this.list.replaceChildren();
  }

  addUser(text) {
    return this.#add("msg msg-user", text);
  }

  addSaki(text = "", { system = false } = {}) {
    return this.#add(system ? "msg msg-saki system" : "msg msg-saki", text);
  }

  addError(message) {
    return this.#add("msg msg-error", message);
  }

  setText(bubble, text) {
    this.#keepScrolled(() => renderText(bubble.querySelector(".body"), text));
  }

  setSystem(bubble, system) {
    bubble.classList.toggle("system", system);
  }

  note(bubble, text) {
    this.#keepScrolled(() => {
      const span = document.createElement("span");
      span.className = "note";
      span.textContent = text;
      bubble.append(span);
    });
  }

  addSources(bubble, sources) {
    if (!Array.isArray(sources) || sources.length === 0) return;
    const ol = document.createElement("ol");
    ol.className = "sources";
    for (const s of sources) {
      const li = document.createElement("li");
      const label =
        `[${s.index}] ${s.title} — ${s.display_url || s.site || ""} (${formatDate(s.date)})` +
        (s.paywalled ? " (trả phí)" : "");
      if (isHttpUrl(s.url)) {
        const a = document.createElement("a");
        a.href = s.url;
        a.target = "_blank";
        a.rel = "noopener noreferrer";
        a.textContent = label;
        li.append(a);
      } else {
        li.textContent = label;
      }
      ol.append(li);
    }
    this.#keepScrolled(() => bubble.append(ol));
  }

  scrollToEnd() {
    this.list.scrollTop = this.list.scrollHeight;
  }

  #add(className, text) {
    const li = document.createElement("li");
    li.className = className;
    const body = document.createElement("div");
    body.className = "body";
    li.append(body);
    renderText(body, text);
    this.#keepScrolled(() => this.list.append(li));
    return li;
  }

  /** Apply a change; stay pinned to the bottom unless the user scrolled up to read. */
  #keepScrolled(change) {
    const { scrollTop, scrollHeight, clientHeight } = this.list;
    const atBottom = scrollHeight - scrollTop - clientHeight < 40;
    change();
    if (atBottom) this.scrollToEnd();
  }
}

/** WebSocket with automatic reconnect (1 s, 2 s, 5 s, then every 10 s). */
export class Connection {
  constructor(url, { onOpen, onClose, onEvent }) {
    this.url = url;
    this.handlers = { onOpen, onClose, onEvent };
    this.ws = null;
    this.attempt = 0;
  }

  get isOpen() {
    return this.ws !== null && this.ws.readyState === WebSocket.OPEN;
  }

  connect() {
    const ws = new WebSocket(this.url);
    this.ws = ws;
    ws.addEventListener("open", () => {
      this.attempt = 0;
      this.handlers.onOpen();
    });
    ws.addEventListener("message", (e) => {
      let event;
      try {
        event = JSON.parse(e.data);
      } catch {
        return;
      }
      if (event && typeof event.type === "string") this.handlers.onEvent(event);
    });
    ws.addEventListener("close", () => {
      if (this.ws !== ws) return;
      this.ws = null;
      this.handlers.onClose();
      const delay = RECONNECT_DELAYS[Math.min(this.attempt++, RECONNECT_DELAYS.length - 1)];
      setTimeout(() => this.connect(), delay);
    });
  }

  send(message) {
    if (!this.isOpen) return false;
    this.ws.send(JSON.stringify(message));
    return true;
  }
}

/**
 * One turn at a time. A message sent while a turn runs first cancels that turn,
 * waits for its terminal event (end, error or cancelled), then goes out.
 */
export class ChatController {
  constructor({ view, character, connection, onChange, onSystemReply, onError }) {
    this.view = view;
    this.character = character;
    this.connection = connection;
    this.onChange = onChange; // (state) => void, state: null | "thinking" | "searching" | "answering"
    this.onSystemReply = onSystemReply;
    this.onError = onError;
    this.turn = null; // { bubble, text, state }
    this.pending = null; // { text, userBubble } waiting for the current turn to end
    this.cancelTimer = null;
  }

  get busy() {
    return this.turn !== null;
  }

  get canSend() {
    return this.connection.isOpen && this.pending === null;
  }

  submit(rawText) {
    const text = rawText.trim();
    if (!text || !this.canSend) return false;
    const userBubble = this.view.addUser(text);
    this.view.scrollToEnd();
    if (this.turn) {
      this.pending = { text, userBubble };
      this.stop();
      this.#changed();
    } else {
      this.#begin(text);
    }
    return true;
  }

  /** Ask the backend to cancel; if no terminal event arrives in time, end the turn locally. */
  stop() {
    if (!this.turn) return;
    this.connection.send({ type: "cancel" });
    clearTimeout(this.cancelTimer);
    this.cancelTimer = setTimeout(() => this.#finish("(đã dừng)"), CANCEL_GRACE_MS);
  }

  handle(event) {
    const turn = this.turn;
    if (!turn) {
      if (event.type === "error") this.view.addError(event.message);
      return;
    }
    switch (event.type) {
      case "status":
        turn.state = event.state === "searching" ? "searching" : "thinking";
        this.character.show("thinking");
        break;
      case "start":
        this.#bubble(event.system);
        turn.state = "answering";
        this.character.show(event.emotion);
        break;
      case "delta":
        turn.text += event.text;
        this.view.setText(this.#bubble(), turn.text);
        break;
      case "reset":
        turn.text = "";
        if (turn.bubble) this.view.setText(turn.bubble, "");
        break;
      case "end": {
        const bubble = this.#bubble(event.system);
        this.view.setText(bubble, event.text);
        this.view.addSources(bubble, event.sources);
        this.#finish();
        this.character.settle(event.emotion);
        if (event.system) this.onSystemReply();
        return;
      }
      case "error":
        if (turn.bubble && !turn.text) turn.bubble.remove();
        this.view.addError(event.message);
        this.#finish();
        this.character.settle("neutral");
        this.onError();
        return;
      case "cancelled":
        this.#finish("(đã dừng)");
        return;
      default:
        return;
    }
    this.#changed();
  }

  /** The socket closed: the running turn is interrupted and a queued message is dropped. */
  disconnected() {
    if (this.pending) this.view.note(this.pending.userBubble, "(chưa gửi được)");
    this.pending = null;
    if (this.turn) this.#finish("(bị gián đoạn)");
    this.#changed();
  }

  #begin(text) {
    this.turn = { bubble: null, text: "", state: "thinking" };
    if (!this.connection.send({ type: "user_message", text })) this.#finish("(chưa gửi được)");
    this.#changed();
  }

  #bubble(system = false) {
    const turn = this.turn;
    if (!turn.bubble) turn.bubble = this.view.addSaki("", { system });
    else this.view.setSystem(turn.bubble, system);
    return turn.bubble;
  }

  #finish(note) {
    clearTimeout(this.cancelTimer);
    const turn = this.turn;
    this.turn = null;
    if (turn && note) {
      this.view.note(this.#ensureBubble(turn), note);
      this.character.settle("neutral");
    }
    const next = this.pending;
    this.pending = null;
    if (next) this.#begin(next.text);
    this.#changed();
  }

  #ensureBubble(turn) {
    if (!turn.bubble) turn.bubble = this.view.addSaki("");
    return turn.bubble;
  }

  #changed() {
    this.onChange(this.turn ? this.turn.state : null);
  }
}
