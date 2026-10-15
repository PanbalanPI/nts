

export function Badge({ children, tone = "gray" }) {
  const tones = {
    green: "bg-emerald-100 text-emerald-800 border-emerald-200",
    red: "bg-rose-100 text-rose-800 border-rose-200",
    amber: "bg-amber-100 text-amber-800 border-amber-200",
    blue: "bg-blue-100 text-blue-800 border-blue-200",
    gray: "bg-slate-100 text-slate-800 border-slate-200",
  };
  
  return (
    <span
      className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium border ${
        tones[tone] || tones.gray
      }`}
    >
      {children}
    </span>
  );
}
