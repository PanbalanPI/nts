
import { CrudPage } from "../components/ui/CrudPage";
import { Badge } from "../components/ui/Badge";

export default function AuditLogPage({ user }) {
  return (
    <CrudPage
      title="Audit Log"
      eyebrow="Security"
      path="/api/audit/"
      canCreate={false}
      user={user}
      columns={[
        { k: "timestamp", l: "Time", render: (r) => new Date(r.timestamp).toLocaleString() },
        { k: "actor_name", l: "Actor", render: (r) => <div className="font-bold text-slate-900">{r.actor_name || `User ${r.actor}`}</div> },
        { k: "action", l: "Action", render: (r) => <Badge tone="blue">{r.action}</Badge> },
        { k: "object_type", l: "Object", render: (r) => <span className="text-slate-600 font-medium">{r.object_type} (ID: {r.object_id})</span> },
      ]}
      fields={[]}
    />
  );
}
