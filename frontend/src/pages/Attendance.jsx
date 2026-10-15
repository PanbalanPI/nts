
import { CrudPage } from "../components/ui/CrudPage";
import { Badge } from "../components/ui/Badge";

export default function AttendancePage({ user }) {
  return (
    <CrudPage
      title="Attendance"
      eyebrow="Personnel"
      path="/api/attendance/"
      user={user}
      columns={[
        { k: "cadet_name", l: "Cadet", render: (r) => <div className="font-bold text-slate-900">{r.cadet_name || `ID: ${r.cadet}`}</div> },
        { k: "date", l: "Date" },
        { k: "status", l: "Status", render: (r) => (
          <Badge tone={r.status === "PRESENT" ? "green" : r.status === "ABSENT" ? "red" : "amber"}>
            {r.status}
          </Badge>
        )},
      ]}
      fields={[]}
    />
  );
}
