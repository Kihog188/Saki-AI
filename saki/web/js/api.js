// REST helpers. Errors carry the backend's Vietnamese `detail` when there is one.

export class ApiError extends Error {}

async function request(method, path, body) {
  const options = { method, headers: {} };
  if (body !== undefined) {
    options.headers["Content-Type"] = "application/json";
    options.body = JSON.stringify(body);
  }
  let res;
  try {
    res = await fetch(path, options);
  } catch {
    throw new ApiError("Không kết nối được với Saki.");
  }
  let data = null;
  try {
    data = await res.json();
  } catch {
    // empty or non-JSON body
  }
  if (!res.ok) {
    if (data && typeof data.detail === "string") throw new ApiError(data.detail);
    throw new ApiError(res.status >= 500 ? "Có lỗi xảy ra, bạn thử lại nhé." : "Dữ liệu không hợp lệ.");
  }
  return data;
}

export const api = {
  health: () => request("GET", "/health"),
  settings: () => request("GET", "/settings"),
  saveSettings: (changes) => request("PUT", "/settings", changes),
  history: (limit = 50) => request("GET", `/history?limit=${limit}`),
  clearHistory: () => request("DELETE", "/history"),
  memories: () => request("GET", "/memories"),
  addMemory: (text) => request("POST", "/memories", { text }),
  deleteMemory: (id) => request("DELETE", `/memories/${encodeURIComponent(id)}`),
  characters: () => request("GET", "/characters"),
  manifest: (packId) => request("GET", `/characters/${encodeURIComponent(packId)}/manifest`),
};
