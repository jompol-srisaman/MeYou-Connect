export type FeatureFlagKey =
  | "founderHome"
  | "candidates"
  | "jobs"
  | "inbox"
  | "clients"
  | "partners"
  | "system"
  | "finance"
  | "payroll"
  | "accounting"
  | "aiMatching"
  | "facebook"
  | "partnerPortal"
  | "candidatePortal";

export const featureFlags: Record<FeatureFlagKey, boolean> = {
  founderHome: true,
  candidates: true,
  jobs: true,
  inbox: true,
  clients: true,
  partners: true,
  system: true,
  finance: false,
  payroll: false,
  accounting: false,
  aiMatching: false,
  facebook: false,
  partnerPortal: false,
  candidatePortal: false,
};

export const killSwitches = {
  allWrites: true,
  offlineMutations: true,
  aiControlledEffects: true,
  productionCutover: true,
} as const;

export function isFeatureEnabled(key: FeatureFlagKey) {
  return featureFlags[key] === true;
}
