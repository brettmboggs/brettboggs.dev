// How an index page lays itself out depends on how much it has to show.
// Up to this many entries it is a spread (src/components/Spread.astro): each
// entry a full plate with its title set large. One more than this and it
// becomes the editorial list, where a row per entry reads faster than a page
// of features. Raise or lower it here; every index reads the same number.
export const SPREAD_UNTIL = 4;

export const useSpread = (count: number): boolean => count > 0 && count <= SPREAD_UNTIL;
