import { useState, useEffect, useMemo } from "react";
import { 
  LayoutDashboard, Flag, Users, FileText, CheckSquare, 
  Activity, CalendarCheck, ShieldCheck, FileKey 
} from "lucide-react";
import { api, handleUnauthorized } from "./api/client";
import { DashboardLayout } from "./layouts/DashboardLayout";
import { LoadingState } from "./components/ui/States";

// Lazy or static page imports (we will build these)
import DashboardPage from "./pages/Dashboard";
import ParadesPage from "./pages/Parades";
import CadetsPage from "./pages/Cadets";
import FlightsPage from "./pages/Flights";
import AttendancePage from "./pages/Attendance";
import FitnessPage from "./pages/Fitness";
import TasksPage from "./pages/Tasks";
import CertificatesPage from "./pages/Certificates";
import NotificationsPage from "./pages/Notifications";
import AuditLogPage from "./pages/AuditLog";
import UsersPage from "./pages/Users";
import Login from "./pages/Login";

function App() {
  const [user, setUser] = useState(() => {
    const saved = localStorage.getItem("nts_user");
    return saved ? JSON.parse(saved) : null;
  });
  const [activePage, setActivePage] = useState("dashboard");
  const [authLoading, setAuthLoading] = useState(!!localStorage.getItem("nts_access"));

  // Check valid token on load if we have one
  useEffect(() => {
    if (user) {
      api.get("/api/auth/me/")
        .then(data => {
          setUser(data);
          localStorage.setItem("nts_user", JSON.stringify(data));
        })
        .catch(() => {
          handleUnauthorized();
        })
        .finally(() => setAuthLoading(false));
    } else {
      setAuthLoading(false);
    }
  }, []);

  const handleLogin = (userData, token) => {
    localStorage.setItem("nts_access", token);
    localStorage.setItem("nts_user", JSON.stringify(userData));
    setUser(userData);
    setActivePage("dashboard");
  };

  const handleLogout = () => {
    handleUnauthorized();
  };

  // Nav Items based on Role
  const navItems = useMemo(() => {
    if (!user) return [];
    
    const role = user.role;
    const isCommand = role === "ANO" || role === "RANKED_SENIOR";
    const isAno = role === "ANO";
    
    const items = [
      { key: "dashboard", label: "Dashboard", icon: LayoutDashboard },
      { key: "parades", label: "Parades", icon: Flag },
      { key: "attendance", label: "Attendance", icon: CalendarCheck },
      { key: "fitness", label: "Fitness", icon: Activity },
      { key: "tasks", label: "Tasks", icon: CheckSquare },
      { key: "cadets", label: "Cadets", icon: Users },
      { key: "flights", label: "Flights", icon: ShieldCheck },
      { key: "certificates", label: "Certificates", icon: FileText },
      { key: "notifications", label: "Notifications", icon: FileKey },
    ];
    
    if (isCommand) {
      items.push({ key: "audit", label: "Audit Log", icon: FileText });
    }
    
    if (isAno) {
      items.push({ key: "users", label: "Users", icon: Users });
    }
    
    return items;
  }, [user]);

  if (authLoading) return <div className="h-screen flex items-center justify-center bg-slate-100"><LoadingState message="Authenticating..." /></div>;
  if (!user) return <Login onLogin={handleLogin} />;

  const pages = {
    dashboard: <DashboardPage user={user} />,
    parades: <ParadesPage user={user} />,
    cadets: <CadetsPage user={user} />,
    flights: <FlightsPage user={user} />,
    attendance: <AttendancePage user={user} />,
    fitness: <FitnessPage user={user} />,
    tasks: <TasksPage user={user} />,
    certificates: <CertificatesPage user={user} />,
    notifications: <NotificationsPage user={user} />,
    audit: <AuditLogPage user={user} />,
    users: <UsersPage user={user} />
  };

  // Fallback to dashboard if a restricted route is somehow active
  const renderPage = pages[activePage] || <DashboardPage user={user} />;

  return (
    <DashboardLayout 
      user={user} 
      onLogout={handleLogout} 
      navItems={navItems}
      activePage={activePage}
      onNavigate={setActivePage}
    >
      {renderPage}
    </DashboardLayout>
  );
}

export default App;
