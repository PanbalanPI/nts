
import { Loader2, AlertTriangle, FileQuestion } from "lucide-react";

export function LoadingState({ message = "Loading..." }) {
  return (
    <div className="flex min-h-[200px] flex-col items-center justify-center p-8 text-slate-500">
      <Loader2 className="mb-4 h-8 w-8 animate-spin text-blue-600" />
      <p className="text-sm font-medium">{message}</p>
    </div>
  );
}

export function ErrorState({ message = "An error occurred", onRetry }) {
  return (
    <div className="flex min-h-[200px] flex-col items-center justify-center rounded-xl border border-rose-200 bg-rose-50 p-8 text-rose-800">
      <AlertTriangle className="mb-4 h-10 w-10 text-rose-600" />
      <p className="mb-4 text-center text-sm font-medium">{message}</p>
      {onRetry && (
        <button
          onClick={onRetry}
          className="rounded-lg bg-rose-600 px-4 py-2 text-sm font-semibold text-white hover:bg-rose-700 transition-colors"
        >
          Try Again
        </button>
      )}
    </div>
  );
}

export function EmptyState({ title = "No data found", description, icon: Icon = FileQuestion, action }) {
  return (
    <div className="flex min-h-[200px] flex-col items-center justify-center rounded-xl border border-dashed border-slate-300 bg-slate-50 p-8 text-slate-500">
      <Icon className="mb-4 h-10 w-10 text-slate-400" />
      <h3 className="mb-1 text-base font-bold text-slate-700">{title}</h3>
      {description && <p className="mb-4 text-sm text-center max-w-sm">{description}</p>}
      {action}
    </div>
  );
}
