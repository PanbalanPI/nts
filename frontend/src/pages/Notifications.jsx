
import { CrudPage } from "../components/ui/CrudPage";
import { Badge } from "../components/ui/Badge";

export default function NotificationsPage({ user }) {
  return (
    <CrudPage
      title="Notifications"
      eyebrow="Command"
      path="/api/notifications/"
      canCreate={false}
      user={user}
      columns={[
        { k: "title", l: "Notification", render: (r) => <div className={`font-${r.read ? "medium text-slate-600" : "bold text-slate-900"}`}>{r.title}</div> },
        { k: "type", l: "Type", render: (r) => <Badge tone="blue">{r.type}</Badge> },
        { k: "created_at", l: "Time", render: (r) => new Date(r.created_at).toLocaleString() },
        { k: "read", l: "Status", render: (r) => (
          <Badge tone={r.read ? "gray" : "amber"}>{r.read ? "Read" : "Unread"}</Badge>
        )},
      ]}
      fields={[]}
    />
  );
}
