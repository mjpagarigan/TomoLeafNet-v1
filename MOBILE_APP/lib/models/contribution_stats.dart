class ContributionStats {
  final int total;
  final int approved;
  final int pendingReview;
  final int usedInTraining;

  const ContributionStats({
    this.total = 0,
    this.approved = 0,
    this.pendingReview = 0,
    this.usedInTraining = 0,
  });
}
