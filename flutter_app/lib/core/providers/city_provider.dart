import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The city currently selected by the user.
/// Shared between FeedPage, MapPage, and FeedNotifier.
const kSupportedCities = ['pune', 'mumbai', 'bangalore'];

final selectedCityProvider = StateProvider<String>((_) => 'pune');
