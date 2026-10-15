import { useState, useEffect, useCallback } from "react";
import { api } from "../../api/client";
import { LoadingState, ErrorState, EmptyState } from "./States";
import { Plus, Search } from "lucide-react";

export function CrudPage({ title, eyebrow, path, columns, canCreate = true, }) {
  const [data, setData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [search, setSearch] = useState("");

  const fetchData = useCallback(async (isRefetch = false) => {
    if (isRefetch) {
      setLoading(true);
      setError("");
    }
    try {
      const res = await api.get(path);
      setData(res.results || res);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, [path]);

  useEffect(() => {
    fetchData(false);
  }, [fetchData]);

  const filtered = data.filter(item => {
    if (!search) return true;
    const term = search.toLowerCase();
    return Object.values(item).some(val => 
      String(val).toLowerCase().includes(term)
    );
  });

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          {eyebrow && <div className="text-blue-600 font-bold tracking-widest text-xs mb-1 uppercase">{eyebrow}</div>}
          <h1 className="text-2xl font-black text-slate-900 tracking-tight">{title}</h1>
        </div>
        {canCreate && (
          <button className="flex items-center gap-2 bg-blue-600 text-white px-4 py-2 rounded-xl font-bold hover:bg-blue-700 transition-colors">
            <Plus size={18} /> Add {title.slice(0, -1)}
          </button>
        )}
      </div>

      <div className="bg-white p-4 rounded-xl shadow-sm border border-slate-200">
        <div className="relative">
          <Search className="absolute left-3 top-2.5 text-slate-400" size={18} />
          <input 
            type="text"
            placeholder={`Search ${title.toLowerCase()}...`}
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="w-full pl-10 pr-4 py-2 bg-slate-50 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 transition-shadow"
          />
        </div>
      </div>

      {loading ? (
        <LoadingState message={`Loading ${title.toLowerCase()}...`} />
      ) : error ? (
        <ErrorState message={error} onRetry={fetchData} />
      ) : filtered.length === 0 ? (
        <EmptyState title={`No ${title.toLowerCase()} found`} description={`Get started by creating a new ${title.slice(0, -1).toLowerCase()}.`} />
      ) : (
        <div className="bg-white rounded-xl shadow-sm border border-slate-200 overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="bg-slate-50 border-b border-slate-200 text-sm text-slate-500 font-bold uppercase tracking-wider">
                {columns.map((col, i) => (
                  <th key={i} className="p-4">{col.l}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {filtered.map((row, i) => (
                <tr key={row.id || i} className="hover:bg-slate-50 transition-colors">
                  {columns.map((col, j) => (
                    <td key={j} className="p-4 text-slate-700">
                      {col.render ? col.render(row) : row[col.k]}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
