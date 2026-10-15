
import { CrudPage } from "../components/ui/CrudPage";
import { Badge } from "../components/ui/Badge";

export default function CertificatesPage({ user }) {
  return (
    <CrudPage
      title="Certificates"
      eyebrow="Recognition"
      path="/api/certificates/"
      user={user}
      columns={[
        { k: "certificate_number", l: "Number", render: (r) => <div className="font-mono text-sm font-bold text-slate-700">{r.certificate_number}</div> },
        { k: "certificate_type", l: "Type", render: (r) => <div className="font-bold text-slate-900">{r.certificate_type}</div> },
        { k: "recipient_name", l: "Recipient", render: (r) => r.recipient_name || `ID: ${r.recipient}` },
        { k: "issue_date", l: "Issued" },
        { k: "status", l: "Status", render: (r) => (
          <Badge tone={r.status === "REVOKED" ? "red" : "green"}>{r.status || "VALID"}</Badge>
        )},
      ]}
      fields={[]}
    />
  );
}
