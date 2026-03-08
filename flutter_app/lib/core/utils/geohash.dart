/// Pure-Dart geohash encoder — no external dependencies.
///
/// Produces a base-32 geohash string from a lat/lng coordinate pair.
/// Precision 7 gives ~150 m accuracy, which matches the Firestore index.
///
/// Reference: https://en.wikipedia.org/wiki/Geohash
library geohash;

const _kBase32 = '0123456789bcdefghjkmnpqrstuvwxyz';

class GeoHash {
  GeoHash._();

  /// Encode [lat] and [lng] as a geohash string.
  ///
  /// [precision] controls string length (and therefore cell size):
  ///   5 → ~4.9 km², 6 → ~1.2 km², 7 → ~152 m²  (default), 8 → ~38 m²
  static String encode(double lat, double lng, {int precision = 7}) {
    assert(lat >= -90 && lat <= 90, 'lat must be in [-90, 90]');
    assert(lng >= -180 && lng <= 180, 'lng must be in [-180, 180]');
    assert(precision >= 1 && precision <= 12, 'precision must be in [1, 12]');

    double minLat = -90, maxLat = 90;
    double minLng = -180, maxLng = 180;

    final result = StringBuffer();
    int bits = 0;
    int hashValue = 0;
    bool isEvenBit = true; // even bits encode longitude, odd bits encode latitude

    while (result.length < precision) {
      final double mid;
      if (isEvenBit) {
        mid = (minLng + maxLng) / 2;
        if (lng >= mid) {
          hashValue = (hashValue << 1) | 1;
          minLng = mid;
        } else {
          hashValue = hashValue << 1;
          maxLng = mid;
        }
      } else {
        mid = (minLat + maxLat) / 2;
        if (lat >= mid) {
          hashValue = (hashValue << 1) | 1;
          minLat = mid;
        } else {
          hashValue = hashValue << 1;
          maxLat = mid;
        }
      }

      isEvenBit = !isEvenBit;
      bits++;

      if (bits == 5) {
        result.write(_kBase32[hashValue]);
        bits = 0;
        hashValue = 0;
      }
    }

    return result.toString();
  }
}
