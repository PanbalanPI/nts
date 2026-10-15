import { useState } from "react";
import { Plane, LogOut, Menu } from "lucide-react";

export function DashboardLayout({ user, onLogout, navItems, activePage, onNavigate, children }) {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  const handleNavClick = (key) => {
    onNavigate(key);
    setMobileMenuOpen(false);
  };

  return (
    <div className="min-h-screen bg-slate-100 text-slate-900">
      {/* Mobile Drawer Overlay */}
      {mobileMenuOpen && (
        <div 
          className="fixed inset-0 z-30 bg-slate-900/50 lg:hidden"
          onClick={() => setMobileMenuOpen(false)}
        />
      )}
      
      <aside
        className={`fixed inset-y-0 left-0 z-40 w-64 bg-slate-950 text-white transition-transform ${
          mobileMenuOpen ? "translate-x-0" : "-translate-x-full"
        } lg:translate-x-0 flex flex-col`}
      >
        <div className="flex h-20 shrink-0 items-center gap-3 border-b border-slate-800 px-5">
          <div className="rounded-xl bg-blue-600 p-2">
            <Plane size={20} />
          </div>
          <div>
            <div className="text-[10px] font-bold tracking-[0.2em] text-blue-300">
              NCC AIR WING
            </div>
            <b className="text-xl">NTS</b>
          </div>
        </div>

        <nav className="flex-1 overflow-y-auto p-3">
          {navItems.map((item) => {
            const Icon = item.icon;
            return (
              <button
                key={item.key}
                type="button"
                onClick={() => handleNavClick(item.key)}
                className={`mb-1 flex w-full items-center gap-3 rounded-xl px-4 py-3 text-sm font-semibold transition-colors ${
                  activePage === item.key
                    ? "bg-blue-600 text-white"
                    : "text-slate-400 hover:bg-slate-800 hover:text-slate-200"
                }`}
              >
                <Icon size={18} />
                {item.label}
              </button>
            );
          })}
        </nav>

        <div className="shrink-0 border-t border-slate-800 p-4">
          <div className="mb-3 text-xs text-slate-400">
            <span className="block font-bold text-slate-200">{user?.first_name || user?.username}</span>
            <span className="uppercase tracking-wider">{user?.role?.replace("_", " ")}</span>
          </div>

          <button
            type="button"
            onClick={onLogout}
            className="flex w-full items-center gap-2 rounded-lg px-2 py-2 text-sm font-medium text-slate-400 hover:bg-slate-800 hover:text-white transition-colors"
          >
            <LogOut size={16} />
            Sign out
          </button>
        </div>
      </aside>

      <div className="lg:pl-64 flex flex-col min-h-screen">
        <header className="sticky top-0 z-20 flex h-20 shrink-0 items-center justify-between border-b bg-white/95 px-4 backdrop-blur md:px-8 shadow-sm">
          <button
            type="button"
            onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
            className="rounded-xl p-2 text-slate-600 hover:bg-slate-100 lg:hidden"
            aria-label="Toggle navigation"
          >
            <Menu />
          </button>

          <div className="font-black tracking-widest text-slate-800 lg:text-lg">NCC AIR WING COMMAND</div>

          <div className="hidden items-center gap-3 md:flex">
            <div className="text-right">
              <b className="block text-sm text-slate-900">
                {user?.first_name || user?.username}
              </b>
              <span className="text-xs font-semibold text-blue-600 uppercase tracking-wide">{user?.role?.replace("_", " ")}</span>
            </div>

            <div className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-slate-900 font-bold text-white shadow-md">
              {(user?.first_name || user?.username || "U")[0].toUpperCase()}
            </div>
          </div>
        </header>

        <main className="flex-1 p-4 md:p-8">
          {children}
        </main>
      </div>
    </div>
  );
}
