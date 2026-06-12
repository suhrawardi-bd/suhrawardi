// football-data.org's `venue` field is a stadium name, often sponsor-branded.
// Hard rule: city-named venues only — so we map stadium -> host city and never
// show the upstream string. Unknown venues degrade to null (counted by the
// sync run) so this map can be extended as real data flows.

const VENUE_CITY: Record<string, string> = {
  // Mexico
  "estadio azteca": "Mexico City",
  "estadio banorte": "Mexico City",
  "estadio ciudad de mexico": "Mexico City",
  "estadio akron": "Guadalajara",
  "estadio guadalajara": "Guadalajara",
  "estadio bbva": "Monterrey",
  "estadio monterrey": "Monterrey",
  // Canada
  "bmo field": "Toronto",
  "toronto stadium": "Toronto",
  "bc place": "Vancouver",
  "bc place vancouver": "Vancouver",
  "vancouver stadium": "Vancouver",
  // United States
  "metlife stadium": "New York",
  "new york new jersey stadium": "New York",
  "sofi stadium": "Los Angeles",
  "los angeles stadium": "Los Angeles",
  "at&t stadium": "Dallas",
  "dallas stadium": "Dallas",
  "nrg stadium": "Houston",
  "houston stadium": "Houston",
  "mercedes-benz stadium": "Atlanta",
  "atlanta stadium": "Atlanta",
  "hard rock stadium": "Miami",
  "miami stadium": "Miami",
  "gillette stadium": "Boston",
  "boston stadium": "Boston",
  "lincoln financial field": "Philadelphia",
  "philadelphia stadium": "Philadelphia",
  "arrowhead stadium": "Kansas City",
  "geha field at arrowhead stadium": "Kansas City",
  "kansas city stadium": "Kansas City",
  "levi's stadium": "San Francisco",
  "san francisco bay area stadium": "San Francisco",
  "lumen field": "Seattle",
  "seattle stadium": "Seattle",
};

export function venueCity(venue: string | null | undefined): string | null {
  if (!venue) return null;
  return VENUE_CITY[venue.trim().toLowerCase()] ?? null;
}
