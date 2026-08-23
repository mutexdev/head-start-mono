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

/** Distance along the polyline from the vertex nearest `pos` to the end. */
export function polylineRemainingMeters(line: LatLng[], pos: LatLng): number {
  if (line.length === 0) return 0;
  let nearest = 0, best = Infinity;
  for (let i = 0; i < line.length; i++) {
    const d = haversineMeters(line[i], pos);
    if (d < best) { best = d; nearest = i; }
  }
  let sum = 0;
  for (let i = nearest; i < line.length - 1; i++) sum += haversineMeters(line[i], line[i + 1]);
  return sum;
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
