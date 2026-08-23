// functions/test/engine/geo.test.ts
import { haversineMeters, decodePolyline, polylineRemainingMeters } from '../../src/engine/geo';

describe('haversineMeters', () => {
  it('is ~0 for identical points', () => {
    expect(haversineMeters({ lat: 1, lng: 1 }, { lat: 1, lng: 1 })).toBeCloseTo(0, 3);
  });
  it('is ~111km per degree latitude', () => {
    const d = haversineMeters({ lat: 0, lng: 0 }, { lat: 1, lng: 0 });
    expect(d).toBeGreaterThan(110_000);
    expect(d).toBeLessThan(112_000);
  });
});

describe('decodePolyline', () => {
  it('decodes the Google reference example (precision 5)', () => {
    const pts = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(pts).toHaveLength(3);
    expect(pts[0].lat).toBeCloseTo(38.5, 3);
    expect(pts[0].lng).toBeCloseTo(-120.2, 3);
    expect(pts[2].lat).toBeCloseTo(43.252, 3);
    expect(pts[2].lng).toBeCloseTo(-126.453, 3);
  });
});

describe('polylineRemainingMeters', () => {
  // straight line north along lng 0 from lat 0 to lat 0.02 (~2.2km), 3 vertices
  const line = [{ lat: 0, lng: 0 }, { lat: 0.01, lng: 0 }, { lat: 0.02, lng: 0 }];
  it('returns full length at the start', () => {
    const m = polylineRemainingMeters(line, { lat: 0, lng: 0 });
    expect(m).toBeGreaterThan(2_200);
    expect(m).toBeLessThan(2_250);
  });
  it('returns roughly half from the midpoint', () => {
    const m = polylineRemainingMeters(line, { lat: 0.01, lng: 0.0001 });
    expect(m).toBeGreaterThan(1_100);
    expect(m).toBeLessThan(1_125);
  });
  it('returns 0 at the end', () => {
    expect(polylineRemainingMeters(line, { lat: 0.02, lng: 0 })).toBeLessThan(5);
  });
});
