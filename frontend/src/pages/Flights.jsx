
import { CrudPage } from "../components/ui/CrudPage";
import { Badge } from "../components/ui/Badge";

export default function FlightsPage({ user }) {
  return (
    <CrudPage
      title="Flights"
      eyebrow="Organization"
      path="/api/flights/"
      user={user}
      columns={[
        { k: "name", l: "Flight Name", render: (r) => <div className="font-bold text-slate-900">{r.name}</div> },
        { k: "code", l: "Code" },
        { k: "flight_senior_name", l: "Flight Senior", render: (r) => r.flight_senior_name || "Unassigned" },
        { k: "active", l: "Status", render: (r) => (
          <Badge tone={r.active ? "green" : "gray"}>{r.active ? "ACTIVE" : "INACTIVE"}</Badge>
        )},
      ]}
      fields={[]}
    />
  );
}
