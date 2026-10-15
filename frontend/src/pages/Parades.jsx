import { useState, useEffect, useCallback, useMemo } from "react";
import { api } from "../api/client";
import { LoadingState, ErrorState, EmptyState } from "../components/ui/States";
import { Badge } from "../components/ui/Badge";
import { Flag, Plus, Search, Eye } from "lucide-react";
import ParadeDetail from "./ParadeDetail";
// Assume we will build a create modal soon, for now just placeholder

export default function Parades({ user }) {
  const [parades, setParades] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("");
  const [selectedParade, setSelectedParade] = useState(null);

  const fetchParades = useCallback(async (isRefetch = false) => {
    if (isRefetch) {
      setLoading(true);
      setError("");
    }
    try {
      const res = await api.get("/api/parades/");
      setParades(res.results || res); // handle pagination if present
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
      }, [fetchParades]);

  const getStatusTone = (status) => {
    switch (status) {
      case "APPROVED": return "green";
      case "REJECTED": return "red";
      case "PENDING_VERIFICATION": return "amber";
      case "COMPLETED": return "blue";
      case "CANCELLED": return "gray";
      default: return "gray";
    }
  };

  const filtered = parades.filter(p => {
    if (statusFilter && p.status !== statusFilter) return false;
    if (search) {
      const term = search.toLowerCase();
      if (!p.title?.toLowerCase().includes(term) && !p.location?.toLowerCase().includes(term)) {
        return false;
      }
    }
    return true;
  });

  if (selectedParade) {
    return <ParadeDetail paradeId={selectedParade.id} user={user} onBack={() => { setSelectedParade(null); fetchParades(); }} />;
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-2xl font-black text-slate-900 tracking-tight">Parades</h1>
          <p className="text-slate-500 font-medium">Command and verify parade workflows</p>
        </div>
        {user.role !== "JUNIOR" && (
          <button className="flex items-center gap-2 bg-blue-600 text-white px-4 py-2 rounded-xl font-bold hover:bg-blue-700 transition-colors">
            <Plus size={18} /> New Parade
          </button>
        )}
      </div>

      <div className="flex flex-col sm:flex-row gap-4 bg-white p-4 rounded-xl shadow-sm border border-slate-200">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-2.5 text-slate-400" size={18} />
          <input 
            type="text"
            placeholder="Search parades..."
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="w-full pl-10 pr-4 py-2 bg-slate-50 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 transition-shadow"
          />
        </div>
        <select 
          value={statusFilter} 
          onChange={e => setStatusFilter(e.target.value)}
          className="bg-slate-50 border border-slate-200 rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 font-medium text-slate-700"
        >
          <option value="">All Statuses</option>
          <option value="DRAFT">Draft</option>
          <option value="PENDING_VERIFICATION">Pending</option>
          <option value="APPROVED">Approved</option>
          <option value="REJECTED">Rejected</option>
          <option value="COMPLETED">Completed</option>
        </select>
      </div>

      {loading ? (
        <LoadingState message="Loading parades..." />
      ) : error ? (
        <ErrorState message={error} onRetry={fetchParades} />
      ) : filtered.length === 0 ? (
        <EmptyState title="No parades found" description="Adjust your filters or create a new parade." icon={Flag} />
      ) : (
        <div className="bg-white rounded-xl shadow-sm border border-slate-200 overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="bg-slate-50 border-b border-slate-200 text-sm text-slate-500 font-bold uppercase tracking-wider">
                <th className="p-4">Title</th>
                <th className="p-4">Type</th>
                <th className="p-4">Date</th>
                <th className="p-4">Status</th>
                <th className="p-4 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {filtered.map(p => (
                <tr key={p.id} className="hover:bg-slate-50 transition-colors">
                  <td className="p-4 font-bold text-slate-900">{p.title}</td>
                  <td className="p-4 font-medium text-slate-600">{p.type}</td>
                  <td className="p-4 text-slate-600">{p.date}</td>
                  <td className="p-4">
                    <Badge tone={getStatusTone(p.status)}>{p.status}</Badge>
                  </td>
                  <td className="p-4 text-right">
                    <button 
                      onClick={() => setSelectedParade(p)}
                      className="inline-flex items-center gap-1 text-blue-600 hover:text-blue-800 font-bold text-sm bg-blue-50 px-3 py-1.5 rounded-lg transition-colors"
                    >
                      <Eye size={16} /> View
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
