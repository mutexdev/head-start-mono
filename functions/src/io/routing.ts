// functions/src/io/routing.ts
import { defineSecret, defineString } from 'firebase-functions/params';
import { LatLng } from '../types';
import { haversineMeters, encodePolyline } from '../engine/geo';

export const GOOGLE_ROUTES_KEY = defineSecret('GOOGLE_ROUTES_KEY');
/** 'google' (default) | 'stub'. Add 'valhalla' etc. later by implementing RoutingProvider. */
export const ROUTING_PROVIDER = defineString('ROUTING_PROVIDER', { default: 'google' });

export interface RouteResult { etaSec: number; distanceM: number; polyline: string }
export interface RoutingProvider { directions(from: LatLng, to: LatLng): Promise<RouteResult> }

/** Google Routes API — Compute Routes v2, traffic-aware. 10k free calls/month on the Essentials SKU. */
export class GoogleRoutesProvider implements RoutingProvider {
  constructor(private readonly apiKey: string) {}
  async directions(from: LatLng, to: LatLng): Promise<RouteResult> {
    const res = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': this.apiKey,
        'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
      },
      body: JSON.stringify({
        origin: { location: { latLng: { latitude: from.lat, longitude: from.lng } } },
        destination: { location: { latLng: { latitude: to.lat, longitude: to.lng } } },
        travelMode: 'DRIVE',
        routingPreference: 'TRAFFIC_AWARE',
        polylineEncoding: 'ENCODED_POLYLINE',
      }),
    });
    if (!res.ok) throw new Error(`google-routes ${res.status}`);
    const json = (await res.json()) as { routes?: { duration: string; distanceMeters: number; polyline: { encodedPolyline: string } }[] };
    const r = json.routes?.[0];
    if (!r) throw new Error('google-routes no-route');
    return { etaSec: parseDurationSec(r.duration), distanceM: Math.round(r.distanceMeters), polyline: r.polyline.encodedPolyline };
  }
}

/** Google returns durations as "1234s" (or "1234.5s"). */
export function parseDurationSec(d: string): number {
  const n = Number(String(d).replace(/s$/, ''));
  if (!Number.isFinite(n)) throw new Error(`bad duration ${d}`);
  return Math.round(n);
}

/** Default road-network detour factor applied to the straight-line distance. */
export const DETOUR_FACTOR = 1.3;
/** Default stub speed, ~43 km/h — plausible mixed urban driving. */
export const DEFAULT_STUB_SPEED_MPS = 12;

/**
 * Distance-aware stub. Needed because a FIXED eta can never drive the alert
 * ladder down to leadTime — an emulator run against the plan's fixed stub would
 * appear to pass while proving nothing about the core product logic.
 *
 * `fixedEtaSec` (ROUTING_STUB_ETA_SEC) still forces the old fixed behaviour so
 * the plan's unit test — eta 170 -> distance 1700 — is preserved.
 *
 * The returned polyline is genuinely encoded so the routing-failure fallback
 * (polylineRemainingMeters over a decoded route) is exercised too.
 */
export class StubProvider implements RoutingProvider {
  constructor(
    private readonly fixedEtaSec: number | undefined,
    private readonly speedMps: number,
  ) {}
  async directions(from: LatLng, to: LatLng): Promise<RouteResult> {
    const distanceM = Math.round(haversineMeters(from, to) * DETOUR_FACTOR);
    const etaSec = this.fixedEtaSec ?? Math.max(1, Math.round(distanceM / this.speedMps));
    return {
      etaSec,
      distanceM: this.fixedEtaSec ? this.fixedEtaSec * 10 : distanceM,
      polyline: encodePolyline([from, to]),
    };
  }
}

export function provider(): RoutingProvider {
  // Order matters: an explicit fixed ETA wins, then the distance-aware stub
  // (explicitly, or implicitly whenever we are inside the emulator — there is no
  // Routes API key here and none may ever be read), then the real provider.
  if (process.env.ROUTING_STUB_ETA_SEC) {
    return new StubProvider(Number(process.env.ROUTING_STUB_ETA_SEC), DEFAULT_STUB_SPEED_MPS);
  }
  if (process.env.ROUTING_STUB_SPEED_MPS || process.env.FUNCTIONS_EMULATOR === 'true') {
    return new StubProvider(undefined, Number(process.env.ROUTING_STUB_SPEED_MPS ?? DEFAULT_STUB_SPEED_MPS));
  }
  switch (ROUTING_PROVIDER.value()) {
    case 'google': return new GoogleRoutesProvider(GOOGLE_ROUTES_KEY.value());
    default: throw new Error(`unknown ROUTING_PROVIDER ${ROUTING_PROVIDER.value()}`);
  }
}

export const directions = (from: LatLng, to: LatLng) => provider().directions(from, to);
