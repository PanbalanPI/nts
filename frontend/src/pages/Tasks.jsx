
import { CrudPage } from "../components/ui/CrudPage";
import { Badge } from "../components/ui/Badge";

export default function TasksPage({ user }) {
  return (
    <CrudPage
      title="Tasks"
      eyebrow="Operations"
      path="/api/tasks/"
      user={user}
      columns={[
        { k: "title", l: "Task", render: (r) => <div className="font-bold text-slate-900">{r.title}</div> },
        { k: "priority", l: "Priority", render: (r) => (
          <Badge tone={r.priority === "HIGH" ? "red" : r.priority === "MEDIUM" ? "amber" : "blue"}>
            {r.priority}
          </Badge>
        )},
        { k: "status", l: "Status", render: (r) => {
          const isOverdue = r.status !== "COMPLETED" && r.due_date && new Date(r.due_date) < new Date();
          if (isOverdue) return <Badge tone="red">OVERDUE</Badge>;
          return <Badge tone={r.status === "COMPLETED" ? "green" : "gray"}>{r.status}</Badge>;
        }},
        { k: "due_date", l: "Due" },
        { k: "assignee_name", l: "Assignee", render: (r) => r.assignee_name || "Unassigned" },
      ]}
      fields={[]}
    />
  );
}
