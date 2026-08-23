// functions/src/engine/geo.ts
import { LatLng } from '../types';

const R = 6_371_000;
const toRad = (d: number) => (d * Math.PI) / 180;

export function haversineMeters(a: LatLng, b: LatLng): number {
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

/** Decodes a Google/Google Routes encoded polyline (precision 5). */
export function decodePolyline(encoded: string): LatLng[] {
  const pts: LatLng[] = [];
  let index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    for (const which of ['lat', 'lng'] as const) {
      let shift = 0, result = 0, byte: number;
      do {
        byte = encoded.charCodeAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      const delta = result & 1 ? ~(result >> 1) : result >> 1;
      if (which === 'lat') lat += delta; else lng += delta;
    }
    pts.push({ lat: lat / 1e5, lng: lng / 1e5 });
  }
  return pts;
}

/**
 * Fraction along segment a->b (clamped to [0,1]) closest to `pos`, via a local
 * equirectangular projection. Segments this function is ever called on are at
 * most a few km, so this planar approximation is well within GPS accuracy.
 */
function projectionFraction(a: LatLng, b: LatLng, pos: LatLng): number {
  const cosLat = Math.cos(toRad(a.lat));
  const bx = (b.lng - a.lng) * cosLat, by = b.lat - a.lat;
  const px = (pos.lng - a.lng) * cosLat, py = pos.lat - a.lat;
  const segLenSq = bx * bx + by * by;
  if (segLenSq === 0) return 0;
  const t = (px * bx + py * by) / segLenSq;
  return Math.max(0, Math.min(1, t));
}

/**
 * Distance along the polyline from the point on the route nearest `pos` to the
 * end. Projects onto each SEGMENT (not just its endpoints) so a position
 * partway along a segment gets a proportionate remaining distance rather than
 * snapping to whichever vertex happens to be closer — on a route with few
 * vertices (e.g. a short, mostly-straight Google Routes polyline, or the
 * emulator's 2-vertex stub), nearest-vertex snapping collapses to 0 for the
 * entire second half of the route, well before actual arrival.
 */
export function polylineRemainingMeters(line: LatLng[], pos: LatLng): number {
  if (line.length < 2) return 0;

  // suffix[i] = distance from vertex i to the end of the line.
  const suffix = new Array<number>(line.length).fill(0);
  for (let i = line.length - 2; i >= 0; i--) {
    suffix[i] = suffix[i + 1] + haversineMeters(line[i], line[i + 1]);
  }

  let bestDist = Infinity;
  let bestRemaining = suffix[0];
  for (let i = 0; i < line.length - 1; i++) {
    const a = line[i], b = line[i + 1];
    const t = projectionFraction(a, b, pos);
    const proj: LatLng = { lat: a.lat + t * (b.lat - a.lat), lng: a.lng + t * (b.lng - a.lng) };
    const dist = haversineMeters(pos, proj);
    if (dist < bestDist) {
      bestDist = dist;
      bestRemaining = haversineMeters(proj, b) + suffix[i + 1];
    }
  }
  return bestRemaining;
}

/** Zig-zag + base64-ish varint for one polyline coordinate delta (precision 5). */
function encodeSignedDelta(delta: number): string {
  let value = delta < 0 ? ~(delta << 1) : delta << 1;
  let out = '';
  while (value >= 0x20) {
    out += String.fromCharCode((0x20 | (value & 0x1f)) + 63);
    value >>= 5;
  }
  out += String.fromCharCode(value + 63);
  return out;
}

/**
 * Encodes points as a Google encoded polyline (precision 5) — the exact inverse
 * of `decodePolyline`, so `decodePolyline(encodePolyline(p)) ≈ p` to 1e-5 deg.
 *
 * Needed because the emulator routing stub has to return a REAL polyline: the
 * routing-failure fallback (`polylineRemainingMeters` over a decoded route) is
 * otherwise never exercised and silently degrades to the haversine branch.
 */
export function encodePolyline(pts: LatLng[]): string {
  let out = '';
  let lastLat = 0;
  let lastLng = 0;
  for (const p of pts) {
    const lat = Math.round(p.lat * 1e5);
    const lng = Math.round(p.lng * 1e5);
    out += encodeSignedDelta(lat - lastLat);
    out += encodeSignedDelta(lng - lastLng);
    lastLat = lat;
    lastLng = lng;
  }
  return out;
}
