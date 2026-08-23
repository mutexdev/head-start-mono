import {
  parseDurationSec,
  StubProvider,
  GoogleRoutesProvider,
  provider,
  DEFAULT_STUB_SPEED_MPS,
} from '../../src/io/routing';
import { encodePolyline, decodePolyline } from '../../src/engine/geo';

const ORIGIN = { lat: 0, lng: 0 };
const DEST = { lat: 0, lng: 0.09 }; // ~10.0 km east on the equator

describe('routing', () => {
  it('parses Google duration strings', () => {
    expect(parseDurationSec('1234s')).toBe(1234);
    expect(parseDurationSec('1234.6s')).toBe(1235);
    expect(() => parseDurationSec('abc')).toThrow();
  });

  it('stub returns fixed eta when one is configured', async () => {
    const r = await new StubProvider(170, DEFAULT_STUB_SPEED_MPS).directions({ lat: 0, lng: 0 }, { lat: 1, lng: 1 });
    expect(r.etaSec).toBe(170);
    expect(r.distanceM).toBe(1700);
  });

  it('distance-aware stub derives a sane eta from haversine * 1.3 / speed', async () => {
    const r = await new StubProvider(undefined, 12).directions(ORIGIN, DEST);
    // ~10.02 km straight line * 1.3 = ~13.0 km, at 12 m/s => ~1085 s
    expect(r.distanceM).toBeGreaterThan(12_500);
    expect(r.distanceM).toBeLessThan(13_500);
    expect(r.etaSec).toBeGreaterThan(900);
    expect(r.etaSec).toBeLessThan(1_300);
  });

  it('distance-aware stub eta shrinks as the origin approaches the destination', async () => {
    const stub = new StubProvider(undefined, 12);
    const far = await stub.directions(ORIGIN, DEST);
    const mid = await stub.directions({ lat: 0, lng: 0.045 }, DEST);
    const near = await stub.directions({ lat: 0, lng: 0.089 }, DEST);
    expect(far.etaSec).toBeGreaterThan(mid.etaSec);
    expect(mid.etaSec).toBeGreaterThan(near.etaSec);
    expect(near.etaSec).toBeGreaterThanOrEqual(1); // never zero
  });

  it('stub returns a genuinely encoded polyline (fallback path needs a real route)', async () => {
    const r = await new StubProvider(undefined, 12).directions(ORIGIN, DEST);
    expect(r.polyline.length).toBeGreaterThan(0);
    const pts = decodePolyline(r.polyline);
    expect(pts).toHaveLength(2);
    expect(pts[1].lat).toBeCloseTo(DEST.lat, 4);
    expect(pts[1].lng).toBeCloseTo(DEST.lng, 4);
  });

  it('encodePolyline round-trips through decodePolyline', () => {
    const pts = [
      { lat: 38.5, lng: -120.2 },
      { lat: 40.7, lng: -120.95 },
      { lat: 43.252, lng: -126.453 },
    ];
    const back = decodePolyline(encodePolyline(pts));
    expect(back).toHaveLength(pts.length);
    back.forEach((p, i) => {
      expect(p.lat).toBeCloseTo(pts[i].lat, 4);
      expect(p.lng).toBeCloseTo(pts[i].lng, 4);
    });
    // matches Google's own reference encoding for the canonical example
    expect(encodePolyline(pts)).toBe('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
  });
});

describe('provider() selection', () => {
  const saved = { ...process.env };
  beforeEach(() => {
    delete process.env.ROUTING_STUB_ETA_SEC;
    delete process.env.ROUTING_STUB_SPEED_MPS;
    delete process.env.FUNCTIONS_EMULATOR;
  });
  afterAll(() => { process.env = { ...saved }; });

  it('ROUTING_STUB_ETA_SEC forces the fixed stub', async () => {
    process.env.ROUTING_STUB_ETA_SEC = '170';
    const p = provider();
    expect(p).toBeInstanceOf(StubProvider);
    const r = await p.directions(ORIGIN, DEST);
    expect(r.etaSec).toBe(170);
    expect(r.distanceM).toBe(1700);
  });

  it('FUNCTIONS_EMULATOR=true selects the distance-aware stub with no key read', async () => {
    process.env.FUNCTIONS_EMULATOR = 'true';
    const p = provider();
    expect(p).toBeInstanceOf(StubProvider);
    const r = await p.directions(ORIGIN, DEST);
    expect(r.etaSec).toBeGreaterThan(900);
  });

  it('ROUTING_STUB_SPEED_MPS alone selects the distance-aware stub at that speed', async () => {
    process.env.ROUTING_STUB_SPEED_MPS = '24';
    const r = await provider().directions(ORIGIN, DEST);
    expect(r.etaSec).toBeGreaterThan(450);
    expect(r.etaSec).toBeLessThan(650);
  });

  it('falls through to the real provider when nothing is stubbed', () => {
    process.env.ROUTING_PROVIDER = 'google';
    process.env.GOOGLE_ROUTES_KEY = 'test-key';
    expect(provider()).toBeInstanceOf(GoogleRoutesProvider);
  });
});
