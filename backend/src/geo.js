const R = 6371;
const rad = (d) => (d * Math.PI) / 180;

export function haversineKm(a, b) {
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/** Straight line x 1.3 approximates road distance in Pakistani cities. */
export const roadKm = (a, b) => Math.round(haversineKm(a, b) * 1.3 * 10) / 10;

export const round10 = (n) => Math.max(10, Math.round(n / 10) * 10);

const RATES = {
  bike: { base: 40, perKm: 18, min: 80 },
  rickshaw: { base: 60, perKm: 25, min: 120 },
  car: { base: 100, perKm: 38, min: 200 },
};

export function suggestFare(vehicleType, km) {
  const r = RATES[vehicleType] ?? RATES.car;
  return round10(Math.max(r.min, r.base + r.perKm * km));
}

export const etaMinutes = (km) => Math.max(1, Math.round((km / 22) * 60));
