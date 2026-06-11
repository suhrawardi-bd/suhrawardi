// football-data.org v4 response shapes (only the fields we consume).

export interface FDTeamRef {
  id: number | null;
  name: string | null;
  tla?: string | null;
}

export interface FDScorePart {
  home: number | null;
  away: number | null;
}

export interface FDScore {
  winner: "HOME_TEAM" | "AWAY_TEAM" | "DRAW" | null;
  duration: "REGULAR" | "EXTRA_TIME" | "PENALTY_SHOOTOUT";
  fullTime: FDScorePart;
  regularTime?: FDScorePart;
  extraTime?: FDScorePart;
  penalties?: FDScorePart;
}

export interface FDMatch {
  id: number;
  utcDate: string;
  status: string;
  matchday: number | null;
  stage: string | null;
  group: string | null;
  lastUpdated: string;
  venue?: string | null;
  homeTeam: FDTeamRef;
  awayTeam: FDTeamRef;
  score: FDScore;
}

export interface FDMatchesResponse {
  matches: FDMatch[];
}

export interface FDTeam {
  id: number;
  name: string;
  shortName?: string;
  tla?: string;
  // `crest` exists upstream but is deliberately not modelled: no team crests.
}

export interface FDTeamsResponse {
  teams: FDTeam[];
}
