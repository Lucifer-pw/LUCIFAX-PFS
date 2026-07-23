import 'dart:math';

/// Data point for K-Means Clustering in Stock Opname Analysis
class KMeansPoint {
  final String productId;
  final String productName;
  final String kodeInduk;
  final double delayDays;       // X1: Delay hari pengiriman vs ERP
  final double totalQtySold;     // X2: Total volume penjualan + sample (Pcs)
  final double crossMonthLagQty; // X3: Volume barang dikirim fisik tapi ERP beda bulan (Pcs)
  final double discrepancyGap;   // X4: Selisih Stok Opname (Pcs)

  int clusterIndex;
  double distanceToCentroid;

  KMeansPoint({
    required this.productId,
    required this.productName,
    required this.kodeInduk,
    required this.delayDays,
    required this.totalQtySold,
    required this.crossMonthLagQty,
    required this.discrepancyGap,
    this.clusterIndex = -1,
    this.distanceToCentroid = 0.0,
  });

  /// Vector representation [X1, X2, X3, X4]
  List<double> toVector() => [delayDays, totalQtySold, crossMonthLagQty, discrepancyGap];

  /// Normalized vector for equal feature weighting
  List<double> toNormalizedVector(List<double> minValues, List<double> maxValues) {
    final vec = toVector();
    final List<double> norm = [];
    for (int i = 0; i < vec.length; i++) {
      final range = maxValues[i] - minValues[i];
      if (range == 0) {
        norm.add(0.0);
      } else {
        norm.add((vec[i] - minValues[i]) / range);
      }
    }
    return norm;
  }
}

/// Result of K-Means Clustering Run
class KMeansResult {
  final List<List<double>> initialCentroids;
  final List<List<double>> finalCentroids;
  final List<KMeansPoint> points;
  final int totalIterations;
  final double silhouetteScore;
  final double sse; // Sum of Squared Errors
  final List<ClusterSummary> clusterSummaries;

  KMeansResult({
    required this.initialCentroids,
    required this.finalCentroids,
    required this.points,
    required this.totalIterations,
    required this.silhouetteScore,
    required this.sse,
    required this.clusterSummaries,
  });
}

class ClusterSummary {
  final int clusterIndex;
  final String label; // e.g. "Risiko Tinggi (Reporting Lag)", "Risiko Sedang", "Risiko Rendah"
  final String colorHex;
  final int productCount;
  final double avgDelayDays;
  final double avgTotalSold;
  final double avgLagQty;
  final double avgDiscrepancyGap;
  final String mainCauseDescription;
  final String recommendation;

  ClusterSummary({
    required this.clusterIndex,
    required this.label,
    required this.colorHex,
    required this.productCount,
    required this.avgDelayDays,
    required this.avgTotalSold,
    required this.avgLagQty,
    required this.avgDiscrepancyGap,
    required this.mainCauseDescription,
    required this.recommendation,
  });
}

class KMeansService {
  /// Euclidean Distance between two vectors
  static double euclideanDistance(List<double> a, List<double> b) {
    double sum = 0.0;
    for (int i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return sqrt(sum);
  }

  /// Min-Max Normalization bounds
  static Map<String, List<double>> computeBounds(List<KMeansPoint> points) {
    if (points.isEmpty) {
      return {
        'min': [0, 0, 0, 0],
        'max': [1, 1, 1, 1],
      };
    }
    final minVals = List<double>.filled(4, double.infinity);
    final maxVals = List<double>.filled(4, -double.infinity);

    for (var p in points) {
      final vec = p.toVector();
      for (int i = 0; i < 4; i++) {
        if (vec[i] < minVals[i]) minVals[i] = vec[i];
        if (vec[i] > maxVals[i]) maxVals[i] = vec[i];
      }
    }
    return {'min': minVals, 'max': maxVals};
  }

  /// Run K-Means Algorithm
  static KMeansResult runKMeans(List<KMeansPoint> inputPoints, {int k = 3, int maxIterations = 100}) {
    if (inputPoints.isEmpty) {
      return KMeansResult(
        initialCentroids: [],
        finalCentroids: [],
        points: [],
        totalIterations: 0,
        silhouetteScore: 0.0,
        sse: 0.0,
        clusterSummaries: [],
      );
    }

    final bounds = computeBounds(inputPoints);
    final minVals = bounds['min']!;
    final maxVals = bounds['max']!;

    // 1. Initial Centroids Selection (K-Means++ or Distributed Spacing)
    final List<List<double>> initialCentroids = [];
    final rand = Random(42); // Fixed seed for reproducible scientific results

    // First centroid: random point
    final firstIdx = rand.nextInt(inputPoints.length);
    initialCentroids.add(List<double>.from(inputPoints[firstIdx].toNormalizedVector(minVals, maxVals)));

    // Choose remaining centroids with probability proportional to distance squared
    while (initialCentroids.length < k && initialCentroids.length < inputPoints.length) {
      final distances = <double>[];
      double totalDistSq = 0.0;

      for (var p in inputPoints) {
        final pNorm = p.toNormalizedVector(minVals, maxVals);
        double minDist = double.infinity;
        for (var c in initialCentroids) {
          final dist = euclideanDistance(pNorm, c);
          if (dist < minDist) minDist = dist;
        }
        final distSq = minDist * minDist;
        distances.add(distSq);
        totalDistSq += distSq;
      }

      if (totalDistSq == 0) {
        // Fallback if all points identical
        initialCentroids.add(List<double>.from(inputPoints[rand.nextInt(inputPoints.length)].toNormalizedVector(minVals, maxVals)));
        continue;
      }

      double target = rand.nextDouble() * totalDistSq;
      int chosenIdx = 0;
      for (int i = 0; i < distances.length; i++) {
        target -= distances[i];
        if (target <= 0) {
          chosenIdx = i;
          break;
        }
      }
      initialCentroids.add(List<double>.from(inputPoints[chosenIdx].toNormalizedVector(minVals, maxVals)));
    }

    // 2. Iteration Loop
    List<List<double>> centroids = initialCentroids.map((c) => List<double>.from(c)).toList();
    int iterationCount = 0;
    bool converged = false;

    while (iterationCount < maxIterations && !converged) {
      iterationCount++;

      // Step A: Assign points to nearest centroid
      for (var p in inputPoints) {
        final pNorm = p.toNormalizedVector(minVals, maxVals);
        double minDist = double.infinity;
        int bestCluster = 0;

        for (int cIdx = 0; cIdx < centroids.length; cIdx++) {
          final dist = euclideanDistance(pNorm, centroids[cIdx]);
          if (dist < minDist) {
            minDist = dist;
            bestCluster = cIdx;
          }
        }
        p.clusterIndex = bestCluster;
        p.distanceToCentroid = minDist;
      }

      // Step B: Recompute centroids
      final newCentroids = List<List<double>>.generate(
        centroids.length,
        (_) => List<double>.filled(4, 0.0),
      );
      final counts = List<int>.filled(centroids.length, 0);

      for (var p in inputPoints) {
        final pNorm = p.toNormalizedVector(minVals, maxVals);
        final cIdx = p.clusterIndex;
        counts[cIdx]++;
        for (int dim = 0; dim < 4; dim++) {
          newCentroids[cIdx][dim] += pNorm[dim];
        }
      }

      for (int cIdx = 0; cIdx < centroids.length; cIdx++) {
        if (counts[cIdx] > 0) {
          for (int dim = 0; dim < 4; dim++) {
            newCentroids[cIdx][dim] /= counts[cIdx];
          }
        } else {
          newCentroids[cIdx] = List<double>.from(centroids[cIdx]);
        }
      }

      // Check convergence
      double maxShift = 0.0;
      for (int cIdx = 0; cIdx < centroids.length; cIdx++) {
        final shift = euclideanDistance(centroids[cIdx], newCentroids[cIdx]);
        if (shift > maxShift) maxShift = shift;
      }

      if (maxShift < 0.0001) {
        converged = true;
      }
      centroids = newCentroids;
    }

    // Compute Sum of Squared Errors (SSE)
    double sse = 0.0;
    for (var p in inputPoints) {
      sse += p.distanceToCentroid * p.distanceToCentroid;
    }

    // Compute Silhouette Coefficient
    final silhouetteScore = _computeSilhouetteScore(inputPoints, bounds);

    // Build Cluster Summaries and auto-interpret labels
    final clusterSummaries = _buildClusterSummaries(inputPoints, centroids, k);

    return KMeansResult(
      initialCentroids: initialCentroids,
      finalCentroids: centroids,
      points: inputPoints,
      totalIterations: iterationCount,
      silhouetteScore: silhouetteScore,
      sse: sse,
      clusterSummaries: clusterSummaries,
    );
  }

  /// Classify new Testing data using trained Centroids
  static List<KMeansPoint> predictTestingData(List<KMeansPoint> testingPoints, List<List<double>> trainedCentroids, Map<String, List<double>> bounds) {
    final minVals = bounds['min']!;
    final maxVals = bounds['max']!;

    for (var p in testingPoints) {
      final pNorm = p.toNormalizedVector(minVals, maxVals);
      double minDist = double.infinity;
      int bestCluster = 0;

      for (int cIdx = 0; cIdx < trainedCentroids.length; cIdx++) {
        final dist = euclideanDistance(pNorm, trainedCentroids[cIdx]);
        if (dist < minDist) {
          minDist = dist;
          bestCluster = cIdx;
        }
      }
      p.clusterIndex = bestCluster;
      p.distanceToCentroid = minDist;
    }
    return testingPoints;
  }

  /// Compute Silhouette Coefficient (-1.0 to 1.0)
  static double _computeSilhouetteScore(List<KMeansPoint> points, Map<String, List<double>> bounds) {
    if (points.length <= 1) return 0.0;

    final minVals = bounds['min']!;
    final maxVals = bounds['max']!;

    final Map<int, List<KMeansPoint>> clusters = {};
    for (var p in points) {
      clusters.putIfAbsent(p.clusterIndex, () => []).add(p);
    }

    if (clusters.keys.length <= 1) return 0.0;

    double totalSilhouette = 0.0;

    for (var p in points) {
      final pNorm = p.toNormalizedVector(minVals, maxVals);
      final ownCluster = clusters[p.clusterIndex] ?? [];

      // a(i): Mean distance to other points in the same cluster
      double a = 0.0;
      if (ownCluster.length > 1) {
        double sumDist = 0.0;
        for (var other in ownCluster) {
          if (other.productId != p.productId) {
            sumDist += euclideanDistance(pNorm, other.toNormalizedVector(minVals, maxVals));
          }
        }
        a = sumDist / (ownCluster.length - 1);
      }

      // b(i): Mean distance to points in the nearest neighboring cluster
      double b = double.infinity;
      for (var entry in clusters.entries) {
        if (entry.key == p.clusterIndex) continue;
        final neighborCluster = entry.value;
        if (neighborCluster.isEmpty) continue;

        double sumDist = 0.0;
        for (var other in neighborCluster) {
          sumDist += euclideanDistance(pNorm, other.toNormalizedVector(minVals, maxVals));
        }
        final avgDist = sumDist / neighborCluster.length;
        if (avgDist < b) b = avgDist;
      }

      final maxAB = max(a, b);
      final s = maxAB == 0 ? 0.0 : (b - a) / maxAB;
      totalSilhouette += s;
    }

    return totalSilhouette / points.length;
  }

  /// Generate Scientific Interpretation per Cluster
  static List<ClusterSummary> _buildClusterSummaries(List<KMeansPoint> points, List<List<double>> centroids, int k) {
    final List<ClusterSummary> summaries = [];

    // Group points by cluster
    final Map<int, List<KMeansPoint>> grouped = {};
    for (int i = 0; i < k; i++) {
      grouped[i] = [];
    }
    for (var p in points) {
      grouped.putIfAbsent(p.clusterIndex, () => []).add(p);
    }

    // Compute averages per cluster
    final List<Map<String, double>> clusterStats = [];
    for (int i = 0; i < k; i++) {
      final cPoints = grouped[i] ?? [];
      double sumDelay = 0;
      double sumSold = 0;
      double sumLag = 0;
      double sumDisc = 0;

      for (var p in cPoints) {
        sumDelay += p.delayDays;
        sumSold += p.totalQtySold;
        sumLag += p.crossMonthLagQty;
        sumDisc += p.discrepancyGap;
      }

      final count = cPoints.length;
      clusterStats.add({
        'index': i.toDouble(),
        'count': count.toDouble(),
        'avgDelay': count > 0 ? sumDelay / count : 0.0,
        'avgSold': count > 0 ? sumSold / count : 0.0,
        'avgLag': count > 0 ? sumLag / count : 0.0,
        'avgDisc': count > 0 ? sumDisc / count : 0.0,
      });
    }

    // Rank clusters by avgLag & avgDelay to assign meaningful labels
    final sortedByRisk = List<Map<String, double>>.from(clusterStats);
    sortedByRisk.sort((a, b) {
      final scoreA = a['avgLag']! * 2 + a['avgDelay']!;
      final scoreB = b['avgLag']! * 2 + b['avgDelay']!;
      return scoreB.compareTo(scoreA); // Highest risk first
    });

    for (int i = 0; i < k; i++) {
      final stats = clusterStats[i];
      final cIdx = i;
      final rankIndex = sortedByRisk.indexWhere((s) => s['index'] == cIdx.toDouble());

      String label;
      String colorHex;
      String causeDesc;
      String recommendation;

      if (rankIndex == 0 && k >= 2) {
        label = 'Cluster $cIdx: Risiko Tinggi (Reporting Lag ERP)';
        colorHex = '#F87171'; // Red
        causeDesc = 'Produk di cluster ini memiliki jeda hari pengiriman fisik vs ERP paling tinggi dan volume penundaan laporan lintas bulan yang signifikan. Hal ini menjadi penyebab utama ketidaksesuaian stok opname.';
        recommendation = 'Lakukan percepatan input invoice ERP untuk pengiriman H-3 akhir bulan dan audit khusus mingguan pada varian produk ini.';
      } else if (rankIndex == k - 1 && k >= 2) {
        label = 'Cluster $cIdx: Risiko Rendah (Stok Akurat & Synchronized)';
        colorHex = '#4ADE80'; // Green
        causeDesc = 'Produk di cluster ini memiliki pencatatan ERP yang real-time dengan tanggal kirim fisik. Selisih stok opname mendekati 0%.';
        recommendation = 'Pertahankan SOP penginputan ERP H-0/H+1 yang sudah berjalan baik pada kelompok barang ini.';
      } else {
        label = 'Cluster $cIdx: Risiko Sedang (Month-End Cut-Off)';
        colorHex = '#FBBF24'; // Amber
        colorHex = '#FBBF24';
        causeDesc = 'Produk di cluster ini mengalami selisih stok sementara akibat jeda waktu cut-off transaksi di 1-2 hari menjelang pergantian bulan.';
        recommendation = 'Terapkan batas waktu cut-off penginputan invoice bulanan pada tanggal 30/31 pukul 23:59 WIB.';
      }

      summaries.add(ClusterSummary(
        clusterIndex: cIdx,
        label: label,
        colorHex: colorHex,
        productCount: stats['count']!.toInt(),
        avgDelayDays: stats['avgDelay']!,
        avgTotalSold: stats['avgSold']!,
        avgLagQty: stats['avgLag']!,
        avgDiscrepancyGap: stats['avgDisc']!,
        mainCauseDescription: causeDesc,
        recommendation: recommendation,
      ));
    }

    return summaries;
  }
}
