export type FixtureStatus =
  | "scheduled"
  | "timed"
  | "in_play"
  | "paused"
  | "finished"
  | "suspended"
  | "postponed"
  | "cancelled"
  | "awarded";

const STATUS_MAP: Record<string, FixtureStatus> = {
  SCHEDULED: "scheduled",
  TIMED: "timed",
  IN_PLAY: "in_play",
  PAUSED: "paused",
  FINISHED: "finished",
  SUSPENDED: "suspended",
  POSTPONED: "postponed",
  CANCELLED: "cancelled",
  AWARDED: "awarded",
};

// null = unknown upstream status; callers count it and fall back safely.
export function mapStatus(upstream: string): FixtureStatus | null {
  return STATUS_MAP[upstream] ?? null;
}
