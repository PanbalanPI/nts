
import { CrudPage } from "../components/ui/CrudPage";
import { Badge } from "../components/ui/Badge";

export default function UsersPage({ user }) {
  return (
    <CrudPage
      title="Users"
      eyebrow="Command"
      path="/api/auth/users/"
      user={user}
      columns={[
        { k: "username", l: "Username", render: (r) => <div className="font-bold text-slate-900">{r.username}</div> },
        { k: "first_name", l: "Name", render: (r) => `${r.first_name} ${r.last_name}` },
        { k: "role", l: "Role", render: (r) => (
          <Badge tone={r.role === "ANO" ? "green" : r.role === "RANKED_SENIOR" ? "blue" : "gray"}>
            {r.role}
          </Badge>
        )},
        { k: "flight", l: "Flight" },
        { k: "is_active", l: "Status", render: (r) => (
          <Badge tone={r.is_active ? "green" : "red"}>{r.is_active ? "Active" : "Inactive"}</Badge>
        )},
      ]}
      fields={[]}
    />
  );
}
