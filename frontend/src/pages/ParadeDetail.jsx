import { useState, useEffect, useCallback, useMemo } from "react";
import { api } from "../api/client";
import { LoadingState, ErrorState } from "../components/ui/States";
import { Badge } from "../components/ui/Badge";
import { Modal } from "../components/ui/Modal";
import { ArrowLeft, CheckCircle, XCircle } from "lucide-react";

export default function ParadeDetail({ paradeId, user, onBack }) {
  const [parade, setParade] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  
  const [actionLoading, setActionLoading] = useState(false);
  const [actionError, setActionError] = useState("");
  
  const [showRejectModal, setShowRejectModal] = useState(false);
  const [rejectionReason, setRejectionReason] = useState("");

  const fetchParade = useCallback(async (isRefetch = false) => {
    if (isRefetch) {
      setLoading(true);
    }
    try {
      const res = await api.get(`/api/parades/${paradeId}/`);
      setParade(res);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, [paradeId]);

  useEffect(() => {
      }, [fetchParade]);

  const handleVerify = async (decision, reason = "") => {
    setActionLoading(true);
    setActionError("");
    try {
      await api.post(`/api/parades/${paradeId}/verify/`, {
        decision,
        reason
      });
      setShowRejectModal(false);
      setRejectionReason("");
      await fetchParade();
    } catch (err) {
      setActionError(err.message);
    } finally {
      setActionLoading(false);
    }
  };

  if (loading) return <LoadingState message="Loading parade details..." />;
  if (error) return <ErrorState message={error} onRetry={fetchParade} />;
  if (!parade) return null;

  // UX Permissions (Backend remains the authority)
  const isPending = parade.status === "PENDING_VERIFICATION";
  const isOfficial = parade.type === "OFFICIAL";
  const isUnofficial = parade.type === "UNOFFICIAL";
  
  const canVerifyOfficial = isOfficial && user.role === "ANO";
  const canVerifyUnofficial = isUnofficial && user.role === "RANKED_SENIOR";
  
  const canVerify = isPending && (canVerifyOfficial || canVerifyUnofficial);
  
  const verificationAuthority = isOfficial ? "ANO" : "RANKED SENIOR";

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <button 
        onClick={onBack}
        className="flex items-center gap-2 text-slate-500 hover:text-slate-800 font-bold text-sm transition-colors"
      >
        <ArrowLeft size={16} /> Back to Parades
      </button>

      {actionError && (
        <div className="bg-rose-50 border border-rose-200 text-rose-800 p-4 rounded-xl text-sm font-medium">
          {actionError}
        </div>
      )}

      <div className="bg-white rounded-2xl shadow-sm border border-slate-200 overflow-hidden">
        <div className="bg-slate-950 p-6 text-white flex justify-between items-start">
          <div>
            <div className="text-blue-400 font-bold tracking-widest text-xs mb-2">
              {parade.type} PARADE
            </div>
            <h1 className="text-3xl font-black">{parade.title}</h1>
          </div>
          <Badge tone={
            parade.status === "APPROVED" ? "green" :
            parade.status === "REJECTED" ? "red" :
            parade.status === "PENDING_VERIFICATION" ? "amber" : "gray"
          }>
            {parade.status}
          </Badge>
        </div>

        <div className="p-6 grid grid-cols-1 md:grid-cols-2 gap-8">
          <div className="space-y-4">
            <div>
              <div className="text-xs font-bold text-slate-400 uppercase">Date & Time</div>
              <div className="font-medium text-slate-800">{parade.date} • {parade.start_time} to {parade.end_time}</div>
            </div>
            <div>
              <div className="text-xs font-bold text-slate-400 uppercase">Location</div>
              <div className="font-medium text-slate-800">{parade.location}</div>
            </div>
            <div>
              <div className="text-xs font-bold text-slate-400 uppercase">Creator</div>
              <div className="font-medium text-slate-800">{parade.creator_name || "Unknown"}</div>
            </div>
            <div>
              <div className="text-xs font-bold text-slate-400 uppercase">Description</div>
              <div className="text-slate-600 mt-1">{parade.description || "No description provided."}</div>
            </div>
          </div>

          <div className="bg-slate-50 p-6 rounded-xl border border-slate-200 space-y-4">
            <h3 className="font-bold text-slate-800 border-b border-slate-200 pb-2">Verification Status</h3>
            
            <div>
              <div className="text-xs font-bold text-slate-400 uppercase">Authority Required</div>
              <div className="font-bold text-slate-900">{verificationAuthority}</div>
            </div>

            {parade.verifier_name && (
              <>
                <div>
                  <div className="text-xs font-bold text-slate-400 uppercase">Verified By</div>
                  <div className="font-medium text-slate-800">{parade.verifier_name}</div>
                </div>
                <div>
                  <div className="text-xs font-bold text-slate-400 uppercase">Verification Time</div>
                  <div className="font-medium text-slate-800">{new Date(parade.verification_time).toLocaleString()}</div>
                </div>
                {parade.rejection_reason && (
                  <div>
                    <div className="text-xs font-bold text-rose-400 uppercase">Rejection Reason</div>
                    <div className="font-medium text-rose-800 bg-rose-50 p-3 rounded-lg mt-1 border border-rose-100">
                      {parade.rejection_reason}
                    </div>
                  </div>
                )}
              </>
            )}

            {canVerify && (
              <div className="pt-4 border-t border-slate-200 flex gap-3">
                <button 
                  onClick={() => handleVerify("APPROVED")}
                  disabled={actionLoading}
                  className="flex-1 bg-emerald-600 hover:bg-emerald-700 text-white font-bold py-2.5 rounded-xl flex items-center justify-center gap-2 transition-colors disabled:opacity-50"
                >
                  <CheckCircle size={18} /> APPROVE
                </button>
                <button 
                  onClick={() => setShowRejectModal(true)}
                  disabled={actionLoading}
                  className="flex-1 bg-rose-600 hover:bg-rose-700 text-white font-bold py-2.5 rounded-xl flex items-center justify-center gap-2 transition-colors disabled:opacity-50"
                >
                  <XCircle size={18} /> REJECT
                </button>
              </div>
            )}
            
            {!canVerify && isPending && (
              <div className="mt-4 text-sm text-slate-500 italic bg-amber-50 text-amber-800 p-3 rounded-lg border border-amber-200">
                This parade is awaiting verification from a {verificationAuthority}.
              </div>
            )}
          </div>
        </div>
      </div>

      {showRejectModal && (
        <Modal title="Reject Parade" onClose={() => setShowRejectModal(false)}>
          <div className="space-y-4">
            <p className="text-sm text-slate-600">
              Please provide a reason for rejecting this parade. This is required and will be recorded in the audit log.
            </p>
            <textarea 
              autoFocus
              className="w-full border border-slate-300 rounded-xl p-3 focus:outline-none focus:ring-2 focus:ring-rose-500"
              rows={4}
              placeholder="Enter rejection reason..."
              value={rejectionReason}
              onChange={e => setRejectionReason(e.target.value)}
            />
            <div className="flex justify-end gap-3 pt-4">
              <button 
                onClick={() => setShowRejectModal(false)}
                className="px-4 py-2 font-bold text-slate-600 hover:bg-slate-100 rounded-lg transition-colors"
              >
                Cancel
              </button>
              <button 
                onClick={() => handleVerify("REJECTED", rejectionReason)}
                disabled={!rejectionReason.trim() || actionLoading}
                className="px-4 py-2 font-bold text-white bg-rose-600 hover:bg-rose-700 rounded-lg transition-colors disabled:opacity-50"
              >
                Confirm Rejection
              </button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}
