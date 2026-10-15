import { useState, useEffect, useCallback, useMemo } from "react";
import { api } from "../api/client";
import { LoadingState, ErrorState, EmptyState } from "../components/ui/States";
import { Users, CalendarCheck, CheckSquare, Flag, Activity, Clock } from "lucide-react";

export default function Dashboard({ user }) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const fetchDashboard = useCallback(async (isRefetch = false) => {
    if (isRefetch) {
      setLoading(true);
      setError("");
    }
    try {
      const res = await api.get("/api/dashboard/");
      const st = res.statistics || {};
      setData({
        ...st,
        role: res.role,
        permissions: res.permissions,
        upcoming_parades: res.upcoming_parades,
        attendance_rate: st.attendance_percentage,
        readiness_rate: st.unit_readiness,
      });
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
      }, [fetchDashboard]);

  if (loading) return <LoadingState message="Loading command metrics..." />;
  if (error) return <ErrorState message={error} onRetry={fetchDashboard} />;
  if (!data) return <EmptyState title="No metrics available" />;

  const isCommand = user.role === "ANO" || user.role === "RANKED_SENIOR";

  return (
    <div className="space-y-6">
      <div className="mb-8">
        <h1 className="text-2xl font-black text-slate-900 tracking-tight">Command Dashboard</h1>
        <p className="text-slate-500 font-medium">Overview for {user.first_name || user.username}</p>
      </div>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        {/* Total Cadets (Command) or Profile Data */}
        {data.total_cadets !== undefined && (
          <div className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
            <div className="flex items-center gap-4 text-blue-600 mb-4">
              <div className="p-3 bg-blue-50 rounded-xl"><Users size={24} /></div>
              <h3 className="font-bold text-slate-700">Total Cadets</h3>
            </div>
            <div className="text-4xl font-black text-slate-900">{data.total_cadets}</div>
          </div>
        )}

        {/* Unit Attendance */}
        {data.attendance_rate !== undefined && (
          <div className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
            <div className="flex items-center gap-4 text-emerald-600 mb-4">
              <div className="p-3 bg-emerald-50 rounded-xl"><CalendarCheck size={24} /></div>
              <h3 className="font-bold text-slate-700">Attendance</h3>
            </div>
            <div className="text-4xl font-black text-slate-900">{data.attendance_rate}%</div>
          </div>
        )}

        {/* Readiness */}
        {data.readiness_rate !== undefined && (
          <div className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
            <div className="flex items-center gap-4 text-indigo-600 mb-4">
              <div className="p-3 bg-indigo-50 rounded-xl"><Activity size={24} /></div>
              <h3 className="font-bold text-slate-700">Readiness</h3>
            </div>
            <div className="text-4xl font-black text-slate-900">{data.readiness_rate}%</div>
          </div>
        )}

        {/* Open Tasks */}
        {data.open_tasks !== undefined && (
          <div className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
            <div className="flex items-center gap-4 text-amber-600 mb-4">
              <div className="p-3 bg-amber-50 rounded-xl"><CheckSquare size={24} /></div>
              <h3 className="font-bold text-slate-700">Open Tasks</h3>
            </div>
            <div className="text-4xl font-black text-slate-900">{data.open_tasks}</div>
            {data.overdue_tasks > 0 && (
              <p className="text-sm font-bold text-rose-600 mt-2">{data.overdue_tasks} OVERDUE</p>
            )}
          </div>
        )}
      </div>

      <div className="grid gap-6 lg:grid-cols-2 mt-8">
        {data.upcoming_parades && (
          <div className="rounded-2xl border border-slate-200 bg-white shadow-sm overflow-hidden">
            <div className="border-b border-slate-100 bg-slate-50/50 p-4 px-6 flex items-center gap-3">
              <Flag size={18} className="text-blue-600" />
              <h3 className="font-bold text-slate-800">Upcoming Parades</h3>
            </div>
            <div className="divide-y divide-slate-100">
              {data.upcoming_parades.length === 0 ? (
                <div className="p-6 text-center text-slate-500">No upcoming parades</div>
              ) : (
                data.upcoming_parades.map(p => (
                  <div key={p.id} className="p-4 px-6 hover:bg-slate-50 flex justify-between items-center">
                    <div>
                      <div className="font-bold text-slate-900">{p.title}</div>
                      <div className="text-sm text-slate-500">{p.date} • {p.type}</div>
                    </div>
                    <span className="text-xs font-bold px-2 py-1 bg-slate-100 rounded-md text-slate-600">
                      {p.status}
                    </span>
                  </div>
                ))
              )}
            </div>
          </div>
        )}

        {isCommand && data.pending_verifications !== undefined && (
          <div className="rounded-2xl border border-slate-200 bg-white shadow-sm overflow-hidden">
            <div className="border-b border-slate-100 bg-slate-50/50 p-4 px-6 flex items-center gap-3">
              <Clock size={18} className="text-amber-600" />
              <h3 className="font-bold text-slate-800">Pending Verification</h3>
            </div>
            <div className="p-6 flex flex-col items-center justify-center min-h-[150px]">
              <div className="text-5xl font-black text-slate-900 mb-2">{data.pending_verifications}</div>
              <p className="text-slate-500 font-medium">Parades awaiting your review</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
