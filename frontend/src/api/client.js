export const API_BASE_URL = import.meta.env.VITE_API_URL || "http://127.0.0.1:8000";

export function getAuthHeaders() {
  const token = localStorage.getItem("nts_access");
  if (!token) return {};
  return { Authorization: `Bearer ${token}` };
}

export function handleUnauthorized() {
  localStorage.removeItem("nts_access");
  localStorage.removeItem("nts_user");
  window.location.reload();
}

async function request(endpoint, options = {}) {
  const url = `${API_BASE_URL}${endpoint}`;
  
  const headers = {
    "Content-Type": "application/json",
    ...getAuthHeaders(),
    ...(options.headers || {}),
  };

  const response = await fetch(url, { ...options, headers });
  
  if (response.status === 401) {
    handleUnauthorized();
    throw new Error("Session expired. Please log in again.");
  }
  
  if (!response.ok) {
    let errorMsg = `Error ${response.status}`;
    try {
      const errorData = await response.json();
      errorMsg = errorData.detail || JSON.stringify(errorData);
    } catch {
      errorMsg = response.statusText || errorMsg;
    }
    throw new Error(errorMsg);
  }
  
  // For 204 No Content
  if (response.status === 204) {
    return null;
  }
  
  return await response.json();
}

export const api = {
  get: (endpoint) => request(endpoint, { method: "GET" }),
  post: (endpoint, data) => request(endpoint, { method: "POST", body: JSON.stringify(data) }),
  put: (endpoint, data) => request(endpoint, { method: "PUT", body: JSON.stringify(data) }),
  patch: (endpoint, data) => request(endpoint, { method: "PATCH", body: JSON.stringify(data) }),
  delete: (endpoint) => request(endpoint, { method: "DELETE" }),
};
