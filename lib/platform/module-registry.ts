import type { FeatureFlagKey } from "@/lib/platform/feature-flags";

export type ModuleStage = "ACTIVE" | "PREVIEW" | "PLANNED";

export interface ModuleRegistration {
  id: string;
  label: string;
  route: string;
  flag: FeatureFlagKey;
  stage: ModuleStage;
  contract: string;
}

export const moduleRegistry: ModuleRegistration[] = [
  { id: "founder-home", label: "Founder Home", route: "/", flag: "founderHome", stage: "ACTIVE", contract: "myc.founder-home.read.v1" },
  { id: "candidates", label: "Candidates", route: "/candidates", flag: "candidates", stage: "PREVIEW", contract: "myc.candidates.read.v1" },
  { id: "jobs", label: "Jobs", route: "/jobs", flag: "jobs", stage: "PREVIEW", contract: "myc.jobs.read.v1" },
  { id: "inbox", label: "Inbox", route: "/inbox", flag: "inbox", stage: "PREVIEW", contract: "myc.inbox.read.v1" },
  { id: "clients", label: "Clients", route: "/clients", flag: "clients", stage: "PREVIEW", contract: "myc.clients.read.v1" },
  { id: "partners", label: "Partners", route: "/partners", flag: "partners", stage: "PREVIEW", contract: "myc.partners.read.v1" },
  { id: "system", label: "System", route: "/system", flag: "system", stage: "PREVIEW", contract: "myc.system.read.v1" },
  { id: "finance", label: "Finance", route: "/finance", flag: "finance", stage: "PLANNED", contract: "myc.finance.read.v1" },
  { id: "payroll", label: "Payroll", route: "/payroll", flag: "payroll", stage: "PLANNED", contract: "myc.payroll.read.v1" },
  { id: "accounting", label: "Accounting", route: "/accounting", flag: "accounting", stage: "PLANNED", contract: "myc.accounting.read.v1" },
  { id: "ai-matching", label: "AI Matching", route: "/ai-matching", flag: "aiMatching", stage: "PLANNED", contract: "myc.ai-matching.read.v1" },
  { id: "partner-portal", label: "Partner Portal", route: "/portal/partner", flag: "partnerPortal", stage: "PLANNED", contract: "myc.partner-portal.v1" },
  { id: "candidate-portal", label: "Candidate Portal", route: "/portal/candidate", flag: "candidatePortal", stage: "PLANNED", contract: "myc.candidate-portal.v1" },
];
