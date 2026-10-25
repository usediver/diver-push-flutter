/// What a Diver campaign notification carries in its data: which campaign
/// it was, and the link it opens, if any.
class DiverCampaignTap {
  const DiverCampaignTap({required this.campaignId, this.uri});

  final String campaignId;

  /// The app link the campaign was composed with — one of the app's own
  /// deeplinks — or null for a notification that just opens the app.
  final Uri? uri;

  /// Reads a notification's data map, as `RemoteMessage.data` hands it over.
  /// Null when this is not a Diver campaign: a message from somewhere else
  /// is somebody else's to handle.
  static DiverCampaignTap? parse(Map<String, Object?> data) {
    final campaignId = data['campaignId'];
    if (campaignId is! String || campaignId.isEmpty) return null;
    final raw = data['uri'];
    final uri = raw is String && raw.isNotEmpty ? Uri.tryParse(raw) : null;
    return DiverCampaignTap(campaignId: campaignId, uri: uri);
  }
}
