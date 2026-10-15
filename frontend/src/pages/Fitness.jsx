
import { CrudPage } from "../components/ui/CrudPage";
import { Badge } from "../components/ui/Badge";

export default function FitnessPage({ user }) {
  return (
    <CrudPage
      title="Fitness"
      eyebrow="Readiness"
      path="/api/fitness/"
      user={user}
      columns={[
        { k: "cadet_name", l: "Cadet", render: (r) => <div className="font-bold text-slate-900">{r.cadet_name || `ID: ${r.cadet}`}</div> },
        { k: "assessment_date", l: "Date" },
        { k: "assessment_type", l: "Assessment" },
        { k: "score", l: "Score", render: (r) => r.score || "-" },
        { k: "status", l: "Status", render: (r) => (
          <Badge tone={r.status === "PASS" ? "green" : r.status === "FAIL" ? "red" : "gray"}>
            {r.status}
          </Badge>
        )},
      ]}
      fields={[]}
    />
  );
}
