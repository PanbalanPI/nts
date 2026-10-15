
import { CrudPage } from "../components/ui/CrudPage";
import { Badge } from "../components/ui/Badge";

export default function CadetsPage({ user }) {
  return (
    <CrudPage
      title="Cadets"
      eyebrow="Personnel"
      path="/api/cadets/"
      user={user}
      columns={[
        { k: "name", l: "Name", render: (r) => <div className="font-bold text-slate-900">{r.name}</div> },
        { k: "roll_number", l: "Roll No." },
        { k: "rank", l: "Rank" },
        { k: "flight", l: "Flight" },
        { k: "status", l: "Status", render: (r) => (
          <Badge tone={r.status === "ACTIVE" ? "green" : "gray"}>{r.status}</Badge>
        )},
      ]}
      fields={[]}
    />
  );
}
