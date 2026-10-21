// Character image for the current emotion, with an idle return to neutral.

import { api } from "./api.js";

export const EMOTIONS = ["neutral", "happy", "sad", "thinking", "surprised", "embarrassed"];
const DEFAULT_PACK = "default";

export class Character {
  constructor(img) {
    this.img = img;
    this.manifest = null;
    this.emotion = "neutral";
    this.idleTimer = null;
    // A file removed after the manifest was read: show the pack's default image instead.
    img.addEventListener("error", () => {
      if (this.manifest && img.getAttribute("src") !== this.manifest.default) {
        img.src = this.manifest.default;
      }
    });
  }

  /** Load a pack by id; an invalid or missing pack falls back to the built-in one. */
  async usePack(packId) {
    let manifest;
    try {
      manifest = await api.manifest(packId || DEFAULT_PACK);
    } catch {
      manifest = await api.manifest(DEFAULT_PACK);
    }
    this.manifest = manifest;
    for (const url of new Set(Object.values(manifest.emotions))) new Image().src = url; // preload
    this.render();
    return manifest.id;
  }

  /** Show an emotion now and keep it (used while a turn is running). */
  show(emotion) {
    clearTimeout(this.idleTimer);
    this.emotion = EMOTIONS.includes(emotion) ? emotion : "neutral";
    this.render();
  }

  /** Show an emotion, then return to neutral after the pack's idle time. */
  settle(emotion) {
    this.show(emotion);
    if (this.emotion === "neutral" || !this.manifest) return;
    this.idleTimer = setTimeout(() => this.show("neutral"), this.manifest.idle_seconds * 1000);
  }

  render() {
    if (!this.manifest) return;
    const url = this.manifest.emotions[this.emotion] || this.manifest.default;
    if (this.img.getAttribute("src") !== url) this.img.src = url;
    this.img.alt = `${this.manifest.name} (${this.emotion})`;
  }
}
