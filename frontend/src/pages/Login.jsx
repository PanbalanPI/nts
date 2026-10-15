import { useState } from "react";
import { Plane, Lock, User } from "lucide-react";
import { API_BASE_URL } from "../api/client";

export default function Login({ onLogin }) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setLoading(true);

    try {
      // Typically /api/auth/login/ returns { access, refresh, user } or similar
      const res = await fetch(`${API_BASE_URL}/api/auth/login/`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, password })
      });
      
      const data = await res.json();
      if (!res.ok) {
        throw new Error(data.detail || "Invalid credentials");
      }
      
      onLogin(data.user || data, data.access);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-950 p-4 font-sans text-slate-100">
      <div className="w-full max-w-md rounded-3xl bg-slate-900 p-8 shadow-2xl ring-1 ring-white/10">
        <div className="mb-10 text-center">
          <div className="mx-auto mb-6 flex h-20 w-20 items-center justify-center rounded-2xl bg-blue-600 shadow-lg shadow-blue-600/20">
            <Plane size={40} className="text-white" />
          </div>
          <h1 className="text-3xl font-black tracking-wider text-white">NTS</h1>
          <p className="mt-2 text-sm font-semibold tracking-widest text-blue-400">
            NCC AIR WING COMMAND
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-6">
          {error && (
            <div className="rounded-xl border border-rose-500/30 bg-rose-500/10 p-4 text-center text-sm font-medium text-rose-400">
              {error}
            </div>
          )}

          <div className="space-y-4">
            <div className="relative">
              <User className="absolute left-4 top-3.5 h-5 w-5 text-slate-500" />
              <input
                autoFocus
                type="text"
                placeholder="Roll Number or Username"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                required
                className="w-full rounded-xl border border-slate-700 bg-slate-950 py-3 pl-12 pr-4 text-white placeholder-slate-500 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500 transition-colors"
              />
            </div>
            
            <div className="relative">
              <Lock className="absolute left-4 top-3.5 h-5 w-5 text-slate-500" />
              <input
                type="password"
                placeholder="Password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                className="w-full rounded-xl border border-slate-700 bg-slate-950 py-3 pl-12 pr-4 text-white placeholder-slate-500 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500 transition-colors"
              />
            </div>
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-xl bg-blue-600 py-3.5 text-sm font-bold tracking-wide text-white transition-colors hover:bg-blue-500 disabled:bg-blue-600/50 disabled:cursor-not-allowed"
          >
            {loading ? "AUTHENTICATING..." : "SECURE LOGIN"}
          </button>
        </form>
        
        <div className="mt-8 text-center text-xs text-slate-600 font-mono tracking-widest">
          SYSTEM V2.0
        </div>
      </div>
    </div>
  );
}
