import 'dart:math';
import 'dart:ui';

class ParsedDetection {
  final String className;
  final Rect box;
  final dynamic raw;

  ParsedDetection({
    required this.className,
    required this.box,
    required this.raw,
  });

  Offset get center => box.center;
  double get area => max(0.0, box.width) * max(0.0, box.height);
}

bool _isHead(String name) =>
    name == 'head_straight' || name == 'head_dropped';

Rect? _readBox(dynamic detection) {
  try {
    final normalized = detection.normalizedBox as Rect?;
    if (normalized != null && normalized.width > 0 && normalized.height > 0) {
      return normalized;
    }
  } catch (_) {}
  try {
    final pixels = detection.boundingBox as Rect?;
    if (pixels != null && pixels.width > 0 && pixels.height > 0) {
      return pixels;
    }
  } catch (_) {}
  return null;
}

/// Prefer the largest, most centered face when several people are in frame.
List<dynamic> selectDriverDetections(List<dynamic> detections) {
  if (detections.length <= 1) return detections;

  final parsed = <ParsedDetection>[];
  for (final detection in detections) {
    final box = _readBox(detection);
    if (box == null) continue;
    parsed.add(
      ParsedDetection(
        className: detection.className.toString(),
        box: box,
        raw: detection,
      ),
    );
  }

  if (parsed.length <= 1) return detections;

  final clusters = _clusterFaces(parsed);
  if (clusters.isEmpty) return detections;
  if (clusters.length == 1) {
    return clusters.first.map((p) => p.raw).toList();
  }

  clusters.sort((a, b) => _clusterScore(b).compareTo(_clusterScore(a)));
  return clusters.first.map((p) => p.raw).toList();
}

List<List<ParsedDetection>> _clusterFaces(List<ParsedDetection> parts) {
  final heads = parts.where((p) => _isHead(p.className)).toList();
  if (heads.isEmpty) {
    return _clusterByProximity(parts);
  }

  final used = <ParsedDetection>{};
  final clusters = <List<ParsedDetection>>[];

  for (final head in heads) {
    final region = _faceRegionForHead(head.box);
    final cluster = <ParsedDetection>[head];
    used.add(head);
    for (final part in parts) {
      if (identical(part, head)) continue;
      if (_isHead(part.className)) continue;
      if (region.contains(part.center)) {
        cluster.add(part);
        used.add(part);
      }
    }
    clusters.add(cluster);
  }

  final leftovers = parts.where((p) => !used.contains(p)).toList();
  if (leftovers.isNotEmpty && clusters.isNotEmpty) {
    for (final leftover in leftovers) {
      clusters.sort((a, b) {
        final da = (a.first.center - leftover.center).distance;
        final db = (b.first.center - leftover.center).distance;
        return da.compareTo(db);
      });
      clusters.first.add(leftover);
    }
  }

  return clusters;
}

Rect _faceRegionForHead(Rect head) {
  final padX = head.width * 0.7;
  final padTop = head.height * 0.4;
  final padBottom = head.height * 1.4;
  return Rect.fromLTRB(
    head.left - padX,
    head.top - padTop,
    head.right + padX,
    head.bottom + padBottom,
  );
}

List<List<ParsedDetection>> _clusterByProximity(List<ParsedDetection> parts) {
  final remaining = [...parts]..sort((a, b) => b.area.compareTo(a.area));
  final clusters = <List<ParsedDetection>>[];
  const maxCenterDistance = 0.22;

  while (remaining.isNotEmpty) {
    final seed = remaining.removeAt(0);
    final cluster = [seed];
    remaining.removeWhere((candidate) {
      final close = (candidate.center - seed.center).distance <= maxCenterDistance;
      if (close) cluster.add(candidate);
      return close;
    });
    clusters.add(cluster);
  }
  return clusters;
}

double _clusterScore(List<ParsedDetection> cluster) {
  var minL = double.infinity, minT = double.infinity;
  var maxR = 0.0, maxB = 0.0;
  for (final part in cluster) {
    minL = min(minL, part.box.left);
    minT = min(minT, part.box.top);
    maxR = max(maxR, part.box.right);
    maxB = max(maxB, part.box.bottom);
  }
  final union = Rect.fromLTRB(minL, minT, maxR, maxB);
  final area = max(0.0, union.width) * max(0.0, union.height);
  final center = union.center;
  final offset = sqrt(pow(center.dx - 0.5, 2) + pow(center.dy - 0.5, 2));
  final maxOffset = sqrt(0.5);
  final centerScore = (1.0 - (offset / maxOffset)).clamp(0.0, 1.0);
  return area * 0.65 + centerScore * 0.35;
}
