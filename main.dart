import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'places_service.dart';
import 'firebase_options.dart';
import 'models/restaurant.dart';
import 'data/seed_data.dart';
import 'data/gesloten.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const HorecaParelsApp());
}

// ── Gedeelde keuken icon helper ───────────────────────────────────────────────
IconData _cuisineIcon(List<String> cuisines) {
  final first = cuisines.isNotEmpty ? cuisines.first.toLowerCase() : '';
  if (first.contains('italiaans') || first.contains('pizza')) return Icons.local_pizza_rounded;
  if (first.contains('japans') || first.contains('sushi')) return Icons.set_meal_rounded;
  if (first.contains('burger') || first.contains('american')) return Icons.lunch_dining_rounded;
  if (first.contains('frans') || first.contains('fine')) return Icons.wine_bar_rounded;
  if (first.contains('tapas') || first.contains('spaans')) return Icons.tapas_rounded;
  if (first.contains('pannenkoek')) return Icons.breakfast_dining_rounded;
  if (first.contains('ijs')) return Icons.icecream_rounded;
  if (first.contains('koffie') || first.contains('bagel')) return Icons.coffee_rounded;
  if (first.contains('streetfood')) return Icons.food_bank_rounded;
  if (first.contains('brasserie') || first.contains('nederland')) return Icons.local_bar_rounded;
  return Icons.restaurant_rounded;
}

// ── Nu open helper ────────────────────────────────────────────────────────────
bool _isNuOpen(Restaurant r) {
  if (r.openingstijden.isEmpty) return false;
  const dayKeys = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
  final dayKey = dayKeys[DateTime.now().weekday - 1];
  final hours = r.openingstijden[dayKey];
  if (hours == null || hours == 'Gesloten') return false;
  final parts = hours.split('–');
  if (parts.length != 2) return false;
  int? parseTime(String t) {
    final tp = t.trim().split(':');
    if (tp.length != 2) return null;
    final h = int.tryParse(tp[0]);
    final m = int.tryParse(tp[1]);
    return (h != null && m != null) ? h * 60 + m : null;
  }
  final open = parseTime(parts[0]);
  var close = parseTime(parts[1]);
  if (open == null || close == null) return false;
  if (close <= open) close += 24 * 60; // middernacht-overgang
  final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;
  return nowMin >= open && nowMin < close;
}

// ── Badge definities ──────────────────────────────────────────────────────────
class _AppBadge {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final bool Function(List<Restaurant> all, Map<String, UserState> user) isEarned;

  const _AppBadge({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.isEarned,
  });
}

final List<_AppBadge> _allBadges = [
  _AppBadge(
    id: 'peerke',
    name: 'Peerke',
    description: 'Je eerste restaurant bezocht',
    icon: Icons.person_rounded,
    isEarned: (all, user) =>
        user.values.where((s) => s.status == VisitStatus.been).isNotEmpty,
  ),
  _AppBadge(
    id: 'dromer',
    name: 'Dromer van de Baronie',
    description: '10 restaurants op je verlanglijst',
    icon: Icons.auto_awesome_rounded,
    isEarned: (all, user) =>
        user.values.where((s) => s.status == VisitStatus.wantToGo).length >= 10,
  ),
  _AppBadge(
    id: 'stadskind',
    name: 'Stadskind van Breda',
    description: '5 restaurants in het Centrum bezocht',
    icon: Icons.location_city_rounded,
    isEarned: (all, user) =>
        all.where((r) =>
            r.wijk == 'Centrum' &&
            (user[r.id]?.status ?? VisitStatus.none) == VisitStatus.been)
        .length >= 5,
  ),
  _AppBadge(
    id: 'ginnekenees',
    name: 'Ginnekenees',
    description: '3 restaurants in het Ginneken bezocht',
    icon: Icons.cottage_rounded,
    isEarned: (all, user) =>
        all.where((r) =>
            r.wijk == 'Ginneken' &&
            (user[r.id]?.status ?? VisitStatus.none) == VisitStatus.been)
        .length >= 3,
  ),
  _AppBadge(
    id: 'princenhagenaar',
    name: 'Princenhagenaar',
    description: '2 restaurants in Princenhage bezocht',
    icon: Icons.home_rounded,
    isEarned: (all, user) =>
        all.where((r) =>
            r.wijk == 'Princenhage' &&
            (user[r.id]?.status ?? VisitStatus.none) == VisitStatus.been)
        .length >= 2,
  ),
  _AppBadge(
    id: 'beekenaar',
    name: 'Beekenaar',
    description: '2 restaurants in Prinsenbeek bezocht',
    icon: Icons.water_rounded,
    isEarned: (all, user) =>
        all.where((r) =>
            r.wijk == 'Prinsenbeek' &&
            (user[r.id]?.status ?? VisitStatus.none) == VisitStatus.been)
        .length >= 2,
  ),
  _AppBadge(
    id: 'belcrummer',
    name: 'Belcrummer',
    description: '2 restaurants in de Belcrum bezocht',
    icon: Icons.warehouse_rounded,
    isEarned: (all, user) =>
        all.where((r) =>
            r.wijk == 'Belcrum' &&
            (user[r.id]?.status ?? VisitStatus.none) == VisitStatus.been)
        .length >= 2,
  ),
  _AppBadge(
    id: 'mamma_mia',
    name: 'Mamma Mia',
    description: '3 Italiaanse restaurants bezocht',
    icon: Icons.local_pizza_rounded,
    isEarned: (all, user) {
      const italiaans = {'Italiaans', 'Pizza', 'Pasta'};
      return all.where((r) =>
          r.cuisines.any(italiaans.contains) &&
          (user[r.id]?.status ?? VisitStatus.none) == VisitStatus.been)
          .length >= 3;
    },
  ),
  _AppBadge(
    id: 'avonturier',
    name: 'Avonturier van de Baronie',
    description: '3 Aziatische restaurants bezocht',
    icon: Icons.hiking_rounded,
    isEarned: (all, user) {
      const aziatisch = {'Aziatisch', 'Japans', 'Sushi', 'Ramen', 'Thais',
          'Vietnamees', 'Chinees', 'Indonesisch', 'Indisch', 'Koreaans',
          'Filipijns', 'Hawaiiaans', 'Poke', 'Hotpot', 'Wok', 'Dim Sum',
          'Fusion', 'Balinees'};
      return all.where((r) =>
          r.cuisines.any(aziatisch.contains) &&
          (user[r.id]?.status ?? VisitStatus.none) == VisitStatus.been)
          .length >= 3;
    },
  ),
  _AppBadge(
    id: 'terrasbourgondier',
    name: 'Terrasbourgondiër',
    description: '3 Mediterrane restaurants bezocht',
    icon: Icons.beach_access_rounded,
    isEarned: (all, user) {
      const mediterraan = {'Mediterraans', 'Grieks', 'Spaans', 'Tapas', 'Frans', 'Bistro'};
      return all.where((r) =>
          r.cuisines.any(mediterraan.contains) &&
          (user[r.id]?.status ?? VisitStatus.none) == VisitStatus.been)
          .length >= 3;
    },
  ),
  _AppBadge(
    id: 'smakenontdekker',
    name: 'Smakenontdekker van Nassau',
    description: '3 Midden-Oosterse restaurants bezocht',
    icon: Icons.dinner_dining_rounded,
    isEarned: (all, user) {
      const middenoosten = {'Midden-Oosters', 'Turks', 'Syrisch', 'Marokkaans',
          'Afghaans', 'Irakees', 'Israëlisch', 'Indiaas', 'Libanees', 'Halal'};
      return all.where((r) =>
          r.cuisines.any(middenoosten.contains) &&
          (user[r.id]?.status ?? VisitStatus.none) == VisitStatus.been)
          .length >= 3;
    },
  ),
  _AppBadge(
    id: 'marktkoning',
    name: 'Marktkoning',
    description: '3 restaurants op de Grote Markt bezocht',
    icon: Icons.storefront_rounded,
    isEarned: (all, user) =>
        all.where((r) =>
            (r.address?.contains('Grote Markt') ?? false) &&
            (user[r.id]?.status ?? VisitStatus.none) == VisitStatus.been)
        .length >= 3,
  ),
  _AppBadge(
    id: 'tafelridder',
    name: 'Tafelridder',
    description: '3 fine dining restaurants bezocht',
    icon: Icons.shield_rounded,
    isEarned: (all, user) =>
        all.where((r) =>
            r.cuisines.contains('Fine dining') &&
            (user[r.id]?.status ?? VisitStatus.none) == VisitStatus.been)
        .length >= 3,
  ),
  _AppBadge(
    id: 'groene_bredanaar',
    name: 'Groene Bredanaar',
    description: '3 vegetarische of vegan restaurants bezocht',
    icon: Icons.eco_rounded,
    isEarned: (all, user) {
      const groen = {'Vegetarisch', 'Vegan', 'Biologisch', 'Gezond'};
      return all.where((r) =>
          r.cuisines.any(groen.contains) &&
          (user[r.id]?.status ?? VisitStatus.none) == VisitStatus.been)
          .length >= 3;
    },
  ),
  _AppBadge(
    id: 'speelhoek_held',
    name: 'Speelhoek Held',
    description: '3 kindvriendelijke restaurants bezocht',
    icon: Icons.toys_rounded,
    isEarned: (all, user) =>
        all.where((r) =>
            r.hasPlayCorner &&
            (user[r.id]?.status ?? VisitStatus.none) == VisitStatus.been)
        .length >= 3,
  ),
  _AppBadge(
    id: 'meester_bourgondier',
    name: 'Meester Bourgondiër',
    description: '5 restaurants met 5 sterren beoordeeld',
    icon: Icons.emoji_events_rounded,
    isEarned: (all, user) =>
        user.values.where((s) => s.rating == 5).length >= 5,
  ),
  _AppBadge(
    id: 'parel',
    name: 'Parel van het Zuiden',
    description: 'Minimaal 8 badges verdiend, waarvan 2+ wijk, 2+ keuken en 1+ thema',
    icon: Icons.diamond_rounded,
    isEarned: (all, user) {
      const wijkBadges = {'stadskind', 'ginnekenees', 'princenhagenaar',
          'beekenaar', 'belcrummer'};
      const keukenBadges = {'mamma_mia', 'avonturier', 'terrasbourgondier',
          'smakenontdekker'};
      const themaBadges = {'marktkoning', 'tafelridder', 'groene_bredanaar',
          'speelhoek_held', 'meester_bourgondier'};
      final earned = <String>{};
      for (final badge in _allBadges) {
        if (badge.id != 'parel' && badge.id != 'dromer' && badge.id != 'peerke') {
          if (badge.isEarned(all, user)) earned.add(badge.id);
        }
      }
      final wijkCount = earned.intersection(wijkBadges).length;
      final keukenCount = earned.intersection(keukenBadges).length;
      final themaCount = earned.intersection(themaBadges).length;
      return earned.length >= 8 && wijkCount >= 2 && keukenCount >= 2 && themaCount >= 1;
    },
  ),
];

// ── Splash screen ─────────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('onboarding_seen') ?? false;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => seen ? const RestaurantListPage() : const _OnboardingPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2D2F6B),
      body: SizedBox.expand(
        child: Image.asset(
          'assets/bash.png',
          fit: BoxFit.cover,
          errorBuilder: (_, err, stack) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}


// ── Kleurenpalet ─────────────────────────────────────────────────────────────
const _navy        = Color(0xFF2D2F6B);
const _navyDark    = Color(0xFF1E205A);
const _orange      = Color(0xFFD4AF6E);
const _gold        = Color(0xFFC9A84C);
const _lavender    = Color(0xFF9B8EC4);
const _cream       = Color(0xFFF8F7F5);
const _cardWhite   = Color(0xEEFFFFFF);
const _heideRoze   = Color(0xFFC4557A); // heide roze — "Geproefd" accent

// ── Categorie filter ─────────────────────────────────────────────────────────
const _cuisineFilterCategories = [
  'Italiaans', 'Aziatisch', 'Mediterraan', 'Burger & Grill',
  'Mexicaans', 'Vegetarisch', 'Ontbijt & Lunch', 'Brasserie & Café',
  'Restaurant', 'Wereldkeuken', 'Koffie',
];

const _cuisineFilterMap = <String, List<String>>{
  'Italiaans':       ['Italiaans', 'Pizza', 'Pizzeria', 'Pasta'],
  'Aziatisch':       ['Japans', 'Sushi', 'Chinees', 'Thais', 'Vietnamees',
                      'Indonesisch', 'Ramen', 'Koreaans', 'Indisch', 'Indiaas',
                      'Aziatisch', 'Poke', 'Wok', 'Hotpot', 'Curry', 'Filipijns'],
  'Mediterraan':     ['Spaans', 'Tapas', 'Frans', 'Bistro', 'Grieks', 'Turks',
                      'Mediterraan', 'Mediterraans', 'Israëlisch', 'Syrisch',
                      'Midden-Oosters', 'Libanees', 'Marokkaans'],
  'Burger & Grill':  ['Burger', 'Grill', 'Steak', 'Amerikaans', 'BBQ',
                      'Hotdog', 'Vlees', 'Kip'],
  'Mexicaans':       ['Mexicaans', 'Burrito', 'Tex-Mex'],
  'Vegetarisch':     ['Vegetarisch', 'Vegan', 'Biologisch', 'Glutenvrij', 'Gezond'],
  'Ontbijt & Lunch': ['Ontbijt', 'Brunch', 'Lunch', 'Koffie', 'Bakkerij',
                      'Bagels', 'Brood', 'Patisserie', 'IJs', 'IJssalon',
                      'Pannenkoeken', 'Juice'],
  'Brasserie & Café':['Brasserie', 'Café', 'Eetcafé', 'Bar', 'GrandCafé',
                      'Pub', 'Brouwerij', 'Bier', 'Cocktails', 'Wijnen',
                      'Nederlands', 'Bourgondisch', 'Borrel'],
  'Restaurant':      ['Restaurant', 'Modern', 'Fusion', 'Finedining', 'Creatief',
                      'Klassiek', 'Shareddining', 'Delicatessen', 'Vis',
                      'All-you-can-eat', 'Snacks', 'Streetfood'],
  'Wereldkeuken':    ['Internationaal', 'Wereldkeuken', 'Afghaans', 'Surinaams',
                      'Pools', 'Hawaiiaans', 'Halal'],
  'Koffie':          ['Koffie'],
};


class HorecaParelsApp extends StatelessWidget {
  const HorecaParelsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Horeca Parels van het Zuiden',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _navy,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.transparent,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
        cardTheme: CardThemeData(
          color: _cardWhite,
          surfaceTintColor: _cardWhite,
          elevation: 2,
          shadowColor: _navy.withValues(alpha: 0.10),
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: _navy.withValues(alpha: 0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: _navy.withValues(alpha: 0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _orange, width: 2),
          ),
          labelStyle: const TextStyle(color: _navy),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _orange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? _orange : _navy.withValues(alpha: 0.35),
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? _orange.withValues(alpha: 0.4)
                : _navy.withValues(alpha: 0.15),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}


// ── Restaurantlijst pagina ────────────────────────────────────────────────────
class RestaurantListPage extends StatefulWidget {
  const RestaurantListPage({super.key});

  @override
  State<RestaurantListPage> createState() => _RestaurantListPageState();
}

class _RestaurantListPageState extends State<RestaurantListPage> {
  static const _restaurantsKey = 'restaurants_v3';
  static const _userKey = 'user_state_v1';


  List<Restaurant> all = [];
  final Map<String, UserState> user = {};
  final Map<String, double> _scoreCache = {};
  final Set<String> _dynamicGesloten = {};

  final Set<String> selectedCuisines = {};
  final Set<String> selectedWijken = {};
  final Set<String> selectedFaciliteiten = {};
  final Set<String> selectedOpenVoor = {};
  bool filterWantToGo = false;
  bool filterNuOpen = false;
  String _sorteerOptie = 'az'; // 'az' of 'rating'
  bool _showTerrasBanner = true;
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  static const _peerkeKey = 'badge_peerke_shown';
  bool _peerkeNotified = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadRestaurants();
    await _loadUserState();
    final prefs = await SharedPreferences.getInstance();
    _peerkeNotified = prefs.getBool(_peerkeKey) ?? false;
    if (!mounted) return;
    setState(() {});
    // Laden vanuit Firestore (handmatig gecureerde data)
    _loadFromFirestore();
    _loadGeslotenFromFirestore();
  }


  Future<void> _loadGeslotenFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('gesloten').get();
      final namen = snapshot.docs
          .map((doc) => doc.data()['naam'] as String?)
          .whereType<String>()
          .toSet();
      if (namen.isNotEmpty) {
        _dynamicGesloten.addAll(namen);
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _loadFromFirestore() async {
    const cacheKey = 'firestore_cache';
    const cacheTimeKey = 'firestore_cache_timestamp';
    const maxAge = 30 * 24 * 60 * 60 * 1000; // 30 dagen in ms

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastFetch = prefs.getInt(cacheTimeKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (now - lastFetch < maxAge) {
        final cached = prefs.getString(cacheKey);
        if (cached != null) {
          debugPrint('[Firestore] Cache gebruiken (jonger dan 30 dagen)');
          final list = jsonDecode(cached) as List<dynamic>;
          final restaurants = <Restaurant>[];
          for (final item in list) {
            try {
              restaurants.add(Restaurant.fromJson(Map<String, dynamic>.from(item as Map)));
            } catch (e) {
              debugPrint('[Firestore] Cache parse fout: $e');
            }
          }
          if (restaurants.isNotEmpty) {
            all = restaurants;
            if (mounted) setState(() {});
          }
          return;
        }
      }

      debugPrint('[Firestore] Cache verlopen of leeg — laden uit Firestore...');
      final snapshot = await FirebaseFirestore.instance
          .collection('restaurants')
          .get();
      if (snapshot.docs.isEmpty) return;
      final firestoreRestaurants = <Restaurant>[];
      final rawList = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          data['id'] = doc.id;
          if (data['createdAt'] == null || data['createdAt'] is! String) {
            data['createdAt'] = DateTime.now().toIso8601String();
          }
          data['city'] ??= 'Breda';
          data['hasPlayCorner'] ??= false;
          data['cuisines'] ??= [];
          firestoreRestaurants.add(Restaurant.fromJson(data));
          rawList.add(data);
        } catch (e) {
          debugPrint('[Firestore] Fout bij laden ${doc.id}: $e');
        }
      }
      if (firestoreRestaurants.isNotEmpty) {
        // Behoud seed-only restaurants die niet in Firestore staan
        final firestoreIds = firestoreRestaurants.map((r) => r.id).toSet();
        final seedOnly = all.where((r) => !firestoreIds.contains(r.id)).toList();
        all = [...firestoreRestaurants, ...seedOnly];
        if (mounted) setState(() {});
        _saveRestaurants();
        await prefs.setString(cacheKey, jsonEncode(rawList));
        await prefs.setInt(cacheTimeKey, now);
        debugPrint('[Firestore] ${firestoreRestaurants.length} restaurants gecached');
      }
    } catch (e) {
      debugPrint('[Firestore] Laad fout: $e');
    }
  }

  Future<void> _fetchPlaceOnDemand(Restaurant r) async {
    if (r.photoName != null) return; // al gecached
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'place_cache_${r.id}';
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        _applyOnePlaceToSeed(r, jsonDecode(cached) as Map<String, dynamic>);
        return;
      }
      final place = await PlacesService.fetchPlaceByName('${r.name} Breda Nederland');
      if (place != null) {
        await prefs.setString(cacheKey, jsonEncode(place));
        _applyOnePlaceToSeed(r, place);
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('[Places] On-demand fetch fout voor ${r.name}: $e');
    }
  }

  void _applyOnePlaceToSeed(Restaurant r, Map<String, dynamic> place) {
    final idx = all.indexWhere((x) => x.id == r.id);
    if (idx < 0) return;

    final address = (place['formattedAddress'] as String?) ?? '';
    final rating = (place['rating'] as num?)?.toDouble();
    final reviews = place['userRatingCount'] as int?;
    final photos = place['photos'] as List?;
    final photoName = photos != null && photos.isNotEmpty
        ? (photos.first as Map)['name'] as String?
        : null;
    final openingHours = place['currentOpeningHours'];
    final website = place['websiteUri'] as String?;
    final location = place['location'] as Map?;
    final lat = (location?['latitude'] as num?)?.toDouble();
    final lng = (location?['longitude'] as num?)?.toDouble();

    debugPrint('[App] Koppeling ${r.name}: foto=${photoName != null}, adres=$address, rating=$rating');

    all[idx] = r.copyWith(
      website: website ?? r.website,
      openingstijden: openingHours != null ? _parseOpeningHours(openingHours) : r.openingstijden,
      googleRating: rating ?? r.googleRating,
      googleReviewCount: reviews ?? r.googleReviewCount,
      photoName: photoName ?? r.photoName,
      address: address.isNotEmpty ? address : r.address,
      lat: lat ?? r.lat,
      lng: lng ?? r.lng,
    );
  }

  Map<String, String> _parseOpeningHours(Map<String, dynamic> openingHours) {
    const dayKeys = ['zo', 'ma', 'di', 'wo', 'do', 'vr', 'za'];
    final result = <String, String>{};
    final periods = openingHours['periods'] as List?;
    if (periods == null) return result;
    for (final period in periods.cast<Map<String, dynamic>>()) {
      final open = period['open'] as Map<String, dynamic>?;
      final close = period['close'] as Map<String, dynamic>?;
      if (open == null) continue;
      final day = (open['day'] as int?) ?? 0;
      final dayKey = dayKeys[day.clamp(0, 6)];
      if (close == null) {
        result[dayKey] = 'Hele dag open';
      } else {
        final oh = (open['hour'] as int? ?? 0).toString().padLeft(2, '0');
        final om = (open['minute'] as int? ?? 0).toString().padLeft(2, '0');
        final ch = (close['hour'] as int? ?? 0).toString().padLeft(2, '0');
        final cm = (close['minute'] as int? ?? 0).toString().padLeft(2, '0');
        result[dayKey] = '$oh:$om\u2013$ch:$cm';
      }
    }
    return result;
  }

  UserState stateFor(String id) => user.putIfAbsent(id, () => UserState());

  List<String> get allCuisineOptions => _cuisineFilterCategories;

  /// Berekent openVoor dynamisch op basis van openingstijden.
  /// Valt terug op r.openVoor als openingstijden leeg zijn.
  List<String> _berekenOpenVoor(Restaurant r) {
    if (r.openingstijden.isEmpty) return r.openVoor;

    final openMinuten = <int>[];
    final sluitMinuten = <int>[];

    for (final value in r.openingstijden.values) {
      if (value == 'Gesloten' || value == 'Hele dag open') continue;
      final parts = value.split('–');
      if (parts.length != 2) continue;
      int? parseMin(String t) {
        final tp = t.trim().split(':');
        if (tp.length != 2) return null;
        final h = int.tryParse(tp[0]);
        final m = int.tryParse(tp[1]);
        return (h != null && m != null) ? h * 60 + m : null;
      }
      final open = parseMin(parts[0]);
      final sluit = parseMin(parts[1]);
      if (open != null) openMinuten.add(open);
      if (sluit != null) sluitMinuten.add(sluit);
    }

    if (openMinuten.isEmpty) return r.openVoor;

    final vroegsteOpen = openMinuten.reduce((a, b) => a < b ? a : b);
    final laastSluit   = sluitMinuten.isNotEmpty
        ? sluitMinuten.reduce((a, b) => a > b ? a : b)
        : 0;

    final result = <String>[];
    if (vroegsteOpen < 11 * 60) result.add('Ontbijt');
    if (vroegsteOpen < 15 * 60) result.add('Lunch');
    if (laastSluit > 17 * 60)   result.add('Diner');
    if (laastSluit > 15 * 60 && laastSluit <= 23 * 60) result.add('Borrel');

    return result.isEmpty ? r.openVoor : result;
  }

  List<Restaurant> get filtered {
    var list = all.where((r) => r.city == 'Breda' &&
        !_dynamicGesloten.any((naam) => r.name.toLowerCase().contains(naam.toLowerCase()))).toList();
    if (filterWantToGo) list = list.where((r) => stateFor(r.id).status == VisitStatus.wantToGo).toList();
    if (filterNuOpen) list = list.where(_isNuOpen).toList();
    if (selectedWijken.isNotEmpty) {
      list = list.where((r) => selectedWijken.contains(r.wijk)).toList();
    }
    if (selectedCuisines.isNotEmpty) {
      final matchLabels = selectedCuisines
          .expand((fc) => _cuisineFilterMap[fc] ?? [fc])
          .toSet();
      list = list
          .where((r) => r.cuisines.any((c) => matchLabels.contains(c)))
          .toList();
    }
    if (selectedFaciliteiten.isNotEmpty) {
      list = list.where((r) {
        for (final f in selectedFaciliteiten) {
          if (f == 'terras' && !r.terras) return false;
          if (f == 'honden' && !r.honden) return false;
          if (f == 'wifi' && !r.wifi) return false;
          if (f == 'rolstoel' && !r.rolstoeltoegankelijk) return false;
          if (f == 'reserveren' && !r.reserveren) return false;
          if (f == 'speelhoek' && !r.hasPlayCorner) return false;
        }
        return true;
      }).toList();
    }
    if (selectedOpenVoor.isNotEmpty) {
      list = list
          .where((r) => _berekenOpenVoor(r).any((o) => selectedOpenVoor.contains(o)))
          .toList();
    }
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      list = list.where((r) {
        return r.name.toLowerCase().contains(q) ||
            r.city.toLowerCase().contains(q) ||
            r.cuisines.any((c) => c.toLowerCase().contains(q));
      }).toList();
    }
    if (_sorteerOptie == 'rating') {
      list.sort((a, b) {
        final ratingA = a.googleRating ?? (stateFor(a.id).rating?.toDouble() ?? 0);
        final ratingB = b.googleRating ?? (stateFor(b.id).rating?.toDouble() ?? 0);
        return ratingB.compareTo(ratingA);
      });
    } else {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  void _invalidateScoreCache() => _scoreCache.clear();

  /// Berekent een persoonlijke score voor één restaurant.
  double _persoonlijkeScore(Restaurant r) {
    if (_scoreCache.containsKey(r.id)) return _scoreCache[r.id]!;
    final rated = all.where((x) => stateFor(x.id).rating != null).toList();
    if (rated.isEmpty) return (r.googleRating ?? 0);

    final cuisineScore = <String, double>{};
    final sfeerScore = <String, double>{};
    final prijsScore = <String, double>{};

    for (final x in rated) {
      final rating = stateFor(x.id).rating ?? 0;
      final gewicht = rating >= 5 ? 2.0 : rating >= 4 ? 1.0 : rating <= 2 ? -1.0 : 0.0;
      for (final c in x.cuisines) { cuisineScore[c] = (cuisineScore[c] ?? 0) + gewicht; }
      for (final s in x.sfeer) { sfeerScore[s] = (sfeerScore[s] ?? 0) + gewicht; }
      if (x.prijs != null) prijsScore[x.prijs!] = (prijsScore[x.prijs!] ?? 0) + gewicht;
    }

    double score = 0;
    // Keukenmatch (zwaarst meegewogen)
    for (final c in r.cuisines) { score += (cuisineScore[c] ?? 0) * 1.5; }
    // Sfeermatch
    for (final s in r.sfeer) { score += (sfeerScore[s] ?? 0) * 1.0; }
    // Prijsmatch
    if (r.prijs != null) score += (prijsScore[r.prijs!] ?? 0) * 0.5;
    // Google rating altijd een basis
    score += (r.googleRating ?? 3.5) * 0.8;

    _scoreCache[r.id] = score;
    return score;
  }

  /// True als dit restaurant een persoonlijke aanrader is (voor badge op kaartje).
  bool _isAanrader(Restaurant r, UserState s) {
    if (s.status == VisitStatus.been) return false;
    final rated = all.where((x) => stateFor(x.id).rating != null).toList();
    // Weinig data: simpele Google-drempel
    if (rated.length < 3) return (r.googleRating ?? 0) >= 4.5;
    // Voldoende data: top 15% van persoonlijke scores én Google >= 4.0
    if ((r.googleRating ?? 0) < 4.0) return false;
    final kandidaten = all.where((x) => stateFor(x.id).status != VisitStatus.been && stateFor(x.id).rating == null).toList();
    if (kandidaten.isEmpty) return false;
    final scores = kandidaten.map(_persoonlijkeScore).toList()..sort((a, b) => b.compareTo(a));
    final drempel = scores.length > 6 ? scores[(scores.length * 0.05).floor()] : scores.last;
    return _persoonlijkeScore(r) >= drempel;
  }

  Future<void> _loadRestaurants() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_restaurantsKey);
    if (raw == null || raw.isEmpty) {
      all = seed.where((r) => !geslotenNamen.contains(r.name)).toList();
      await _saveRestaurants();
      return;
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final saved = decoded
          .map((e) => Restaurant.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      // Voeg nieuwe seeds toe die nog niet in de opgeslagen lijst staan
      final savedIds = saved.map((r) => r.id).toSet();
      final newSeeds = seed
          .where((r) => !savedIds.contains(r.id) && !geslotenNamen.contains(r.name))
          .toList();
      all = [...saved, ...newSeeds];
      if (newSeeds.isNotEmpty) {
        debugPrint('[App] ${newSeeds.length} nieuwe seed(s) toegevoegd: ${newSeeds.map((r) => r.name).join(', ')}');
        await _saveRestaurants();
      }
    } catch (_) {
      all = seed.where((r) => !geslotenNamen.contains(r.name)).toList();
      await _saveRestaurants();
    }
  }

  Future<void> _saveRestaurants() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _restaurantsKey, jsonEncode(all.map((r) => r.toJson()).toList()));
  }

  Future<void> _loadUserState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((id, value) {
        if (value is Map) {
          user[id] = UserState.fromJson(Map<String, dynamic>.from(value));
        }
      });
    } catch (_) {}
  }

  Future<void> _saveUserState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _userKey, jsonEncode(user.map((id, s) => MapEntry(id, s.toJson()))));
  }

  Future<void> _persistUser() async {
    if (!mounted) return;
    _invalidateScoreCache();
    setState(() {});
    await _saveUserState();
    if (!_peerkeNotified) {
      final peerke = _allBadges.firstWhere((b) => b.id == 'peerke');
      if (peerke.isEarned(all, user)) {
        _peerkeNotified = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_peerkeKey, true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Welkom in de Baronie, Peerke!'),
              backgroundColor: _gold,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }


  Color _statusColor(VisitStatus s) {
    switch (s) {
      case VisitStatus.wantToGo:
        return _heideRoze;
      case VisitStatus.been:
        return _gold;
      case VisitStatus.none:
        return Colors.transparent;
    }
  }

  String _statusLabel(VisitStatus s) {
    switch (s) {
      case VisitStatus.none:
        return '';
      case VisitStatus.wantToGo:
        return 'Nog proeven';
      case VisitStatus.been:
        return 'Al geproefd';
    }
  }

  bool get _hasActiveFilters =>
      searchQuery.isNotEmpty ||
      selectedCuisines.isNotEmpty ||
      selectedWijken.isNotEmpty ||
      filterWantToGo ||
      filterNuOpen ||
      selectedFaciliteiten.isNotEmpty ||
      selectedOpenVoor.isNotEmpty;

  int get _activeFilterCount =>
      (selectedCuisines.isNotEmpty ? 1 : 0) +
      (selectedWijken.isNotEmpty ? 1 : 0) +
      (filterNuOpen ? 1 : 0) +
      (selectedFaciliteiten.isNotEmpty ? 1 : 0) +
      (selectedOpenVoor.isNotEmpty ? 1 : 0);

  void _openSorteerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _navyDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Sorteren', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              _SorteerOptieRij(
                label: 'Sorteer op A-Z',
                selected: _sorteerOptie == 'az',
                onTap: () {
                  setState(() => _sorteerOptie = 'az');
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 10),
              _SorteerOptieRij(
                label: 'Sorteer op ★ Score',
                selected: _sorteerOptie == 'rating',
                onTap: () {
                  setState(() => _sorteerOptie = 'rating');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _navyDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void toggle(Set<String> set, String val) {
            setSheet(() { if (set.contains(val)) { set.remove(val); } else { set.add(val); } });
            setState(() {});
          }
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            maxChildSize: 0.92,
            minChildSize: 0.4,
            builder: (_, sc) => Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Text('Filters', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      if (_hasActiveFilters)
                        GestureDetector(
                          onTap: () { _clearAllFilters(); setSheet(() {}); },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('Wis alle filters', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Divider(color: Colors.white12, height: 1),
                // Scrollable content
                Expanded(
                  child: ListView(
                    controller: sc,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      // ── Nu open toggle ──
                      Row(
                        children: [
                          const Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Nu open', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                              Text('Alleen restaurants die nu open zijn', style: TextStyle(color: Colors.white54, fontSize: 12)),
                            ],
                          )),
                          Switch(
                            value: filterNuOpen,
                            onChanged: (v) { setSheet(() => filterNuOpen = v); setState(() {}); },
                            activeThumbColor: _gold,
                            activeTrackColor: _gold.withValues(alpha: 0.3),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Divider(color: Colors.white12, height: 1),
                      const SizedBox(height: 16),
                      // ── Wanneer ga je? ──
                      const Text('WANNEER GA JE?', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: [
                          for (final o in ['Ontbijt', 'Lunch', 'Diner', 'Borrel'])
                            _SheetChip(label: o, isActive: selectedOpenVoor.contains(o), onTap: () => toggle(selectedOpenVoor, o)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // ── Keuken ──
                      const Text('CATEGORIE', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: [
                          for (final c in allCuisineOptions)
                            _SheetChip(label: c, isActive: selectedCuisines.contains(c), onTap: () => toggle(selectedCuisines, c)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // ── Faciliteiten ──
                      const Text('FACILITEITEN', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: [
                          for (final f in [('terras','Terras'), ('honden','Honden'), ('wifi','Wifi'), ('rolstoel','Rolstoeltoeg.'), ('reserveren','Reserveren'), ('speelhoek','Speelhoek')])
                            _SheetChip(label: f.$2, isActive: selectedFaciliteiten.contains(f.$1), onTap: () => toggle(selectedFaciliteiten, f.$1)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // ── Wijk ──
                      const Text('WIJK', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: [
                          for (final w in ['Boeimeer', 'Centrum', 'Ginneken', 'Haagdijk', 'Overig', 'Princenhage', 'Tuinzigt'])
                            _SheetChip(label: w, isActive: selectedWijken.contains(w), onTap: () => toggle(selectedWijken, w)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // ── Resultaten knop ──
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _gold,
                            foregroundColor: _navy,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text('Toon ${filtered.length} restaurants', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _clearAllFilters() {
    setState(() {
      searchQuery = '';
      _searchController.clear();
      selectedCuisines.clear();
      selectedWijken.clear();
      selectedFaciliteiten.clear();
      selectedOpenVoor.clear();
      filterWantToGo = false;
      filterNuOpen = false;
    });
  }

  // Stats voor de header
  int get _beenCount => user.values.where((s) => s.status == VisitStatus.been).length;
  int get _wantToGoCount => user.values.where((s) => s.status == VisitStatus.wantToGo).length;

  void _showLogoMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: _navyDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              controller: scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── MIJN PROFIEL ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('MIJN PROFIEL', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              ),
              ListTile(
                leading: const Icon(Icons.tune_rounded, color: _gold),
                title: const Text('Mijn voorkeuren', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Jouw Bourgondische profiel', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _VoorkeureNPage()));
                },
              ),

              const Divider(color: Colors.white12, height: 1),

              // ── JOUW PARELS ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('JOUW PARELS', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_border_rounded, color: _gold),
                title: const Text('Nog proeven', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: Text('$_wantToGoCount restaurants op je lijstje', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _WilIkHeenPage(all: all, user: user, onChanged: _persistUser),
                  ));
                },
              ),
              ListTile(
                leading: const Icon(Icons.check_circle_outline_rounded, color: _gold),
                title: const Text('Al geproefd', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: Text('$_beenCount bezochte restaurants', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _GeweestPage(all: all, user: user, onChanged: _persistUser),
                  ));
                },
              ),

              const Divider(color: Colors.white12, height: 1),

              // ── ONTDEK ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('ONTDEK', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              ),
              ListTile(
                leading: const Icon(Icons.shuffle_rounded, color: _gold),
                title: const Text('Verras me', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Willekeurig restaurant uit de hele lijst', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  _openRandom(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.near_me_rounded, color: _gold),
                title: const Text('Verras me in de buurt', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Restaurant binnen 500 meter', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  _openRandomNearby(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.map_rounded, color: _gold),
                title: const Text('Kaart', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Alle parels op de kaart', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _MapPage(
                      restaurants: all,
                      stateFor: stateFor,
                      onChanged: _persistUser,
                    ),
                  ));
                },
              ),

              const Divider(color: Colors.white12, height: 1),

              // ── DENK MEE ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('DOE MEE', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              ),
              ListTile(
                leading: const Icon(Icons.edit_note_rounded, color: _gold),
                title: const Text('Neem contact op', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Dit klopt niet, er ontbreekt iets, suggestie of feedback', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StelVoorPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.star_outline_rounded, color: _gold),
                title: const Text('Parel in de spotlight', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Voor horecaondernemers', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _SpotlightPage()));
                },
              ),

              const Divider(color: Colors.white12, height: 1),

              // ── OVER HPvhZ ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('OVER HPvhZ', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_rounded, color: _gold),
                title: const Text('Over Horeca Parels van het Zuiden', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Waarom bestaat deze app?', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _InHetLichtPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.coffee_rounded, color: _gold),
                title: const Text('Blij met deze app?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Trakteer de Bourgondiër', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _FeedbackPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined, color: _gold),
                title: const Text('Privacybeleid', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Hoe we omgaan met jouw gegevens', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _PrivacyPage()));
                },
              ),


              const SizedBox(height: 16),
            ],
          ),
        ),
        ),
        ),
      ),
    );
  }

  Future<void> _openRandom(BuildContext context) async {
    final list = all;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geen restaurants om uit te kiezen')),
      );
      return;
    }
    final r = list[Random().nextInt(list.length)];
    await _fetchPlaceOnDemand(r);
    final updated = all.firstWhere((x) => x.id == r.id, orElse: () => r);
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RestaurantDetailPage(
        restaurant: updated,
        state: stateFor(updated.id),
        onChanged: _persistUser,
        allRestaurants: all,
        resolveState: stateFor,
      ),
    ));
  }

  Future<void> _openRandomNearby(BuildContext context) async {
    // Locatietoestemming ophalen
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Locatietoestemming geweigerd. Geef toestemming in instellingen.'),
          ),
        );
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📍 Locatie ophalen...'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kon locatie niet ophalen. Probeer opnieuw.')),
        );
      }
      return;
    }

    // Filter restaurants met coördinaten binnen 500m
    const maxMeters = 500.0;
    final nearby = all.where((r) {
      if (r.lat == null || r.lng == null) return false;
      final dist = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, r.lat!, r.lng!,
      );
      return dist <= maxMeters;
    }).toList();

    if (nearby.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Geen restaurants binnen 500 meter gevonden. Ben je in Breda? 😄'),
          ),
        );
      }
      return;
    }

    final r = nearby[Random().nextInt(nearby.length)];
    await _fetchPlaceOnDemand(r);
    final updated = all.firstWhere((x) => x.id == r.id, orElse: () => r);
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RestaurantDetailPage(
          restaurant: updated,
          state: stateFor(updated.id),
          onChanged: _persistUser,
          allRestaurants: all,
          resolveState: stateFor,
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = filtered;

    return Scaffold(
      backgroundColor: _cream,
      body: Stack(
        children: [
          // image.png achtergrond (geen overlay)
          Positioned.fill(
            child: Column(
              children: [
                SizedBox(height: kToolbarHeight + MediaQuery.of(context).padding.top),
                Expanded(
                  child: Image.asset(
                    'assets/image.png',
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, err, stack) => Container(color: _cream),
                  ),
                ),
              ],
            ),
          ),
          RefreshIndicator(
        color: _gold,
        backgroundColor: Colors.transparent,
        onRefresh: () async {
          await _loadUserState();
          if (mounted) setState(() {});
        },
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          interactive: true,
          thickness: 4,
          radius: const Radius.circular(2),
          child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
          // ── Hero appbar met banner + zoekbalk + filters ──
          SliverAppBar(
            expandedHeight: 0,
            floating: false,
            pinned: true,
            backgroundColor: _navy,
            foregroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            leadingWidth: 56,
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 26),
              onPressed: () => _showLogoMenu(context),
            ),
            actions: const [],
            title: const Text(
              'Horeca Parels van het Zuiden',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(100),
              child: Container(
                decoration: const BoxDecoration(color: _navy),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 40,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Zoek op naam, categorie...',
                          prefixIcon: Icon(Icons.search, color: _navy, size: 18),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 11),
                          hintStyle: TextStyle(color: _navy, fontSize: 13),
                        ),
                        style: const TextStyle(color: _navy, fontSize: 13),
                        onChanged: (v) => setState(() => searchQuery = v),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                      children: [
                        // Filter knop
                        GestureDetector(
                          onTap: () => _openFilterSheet(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: _hasActiveFilters ? _gold : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _hasActiveFilters ? _gold : Colors.white30),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.tune_rounded, size: 14, color: _hasActiveFilters ? _navy : Colors.white),
                                const SizedBox(width: 5),
                                Text(
                                  _hasActiveFilters ? 'Filters ($_activeFilterCount)' : 'Filter',
                                  style: TextStyle(color: _hasActiveFilters ? _navy : Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_hasActiveFilters) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: _clearAllFilters,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white38),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.close_rounded, size: 12, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text('Wis filters', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (filterNuOpen) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => setState(() => filterNuOpen = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: _heideRoze,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.circle, size: 8, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text('Nu open', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        // Sorteer knop
                        GestureDetector(
                          onTap: () => _openSorteerSheet(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white30),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Sorteer',
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(width: 3),
                                const Icon(Icons.expand_more_rounded, size: 14, color: Colors.white70),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('${results.length}', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
                        const SizedBox(width: 8),
                      ],
                    ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bourgondisch terras banner ──
          if (_showTerrasBanner &&
              DateTime.now().month >= 5 &&
              DateTime.now().month <= 9)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _gold.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wb_sunny_rounded,
                          color: _gold, size: 18),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Bourgondisch terrasweer! De terrassen op de Grote Markt lonken...',
                          style: TextStyle(
                            color: _navy,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded,
                            size: 18, color: _navy.withValues(alpha: 0.4)),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () =>
                            setState(() => _showTerrasBanner = false),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Parels die bij jou kunnen passen carousel ──
          SliverToBoxAdapter(
            child: _ProfielCarousel(
              all: all,
              stateFor: stateFor,
              onChanged: _persistUser,
            ),
          ),

          // ── Restaurant lijst ──
          results.isEmpty
              ? SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off,
                            size: 48, color: _navy.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text(
                          'Nog geen parels ontdekt\nin de Baronie...',
                          style: TextStyle(
                              color: _navy.withValues(alpha: 0.5), fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final r = results[i];
                        final s = stateFor(r.id);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _RestaurantCard(
                            restaurant: r,
                            state: s,
                            statusColor: _statusColor(s.status),
                            statusLabel: _statusLabel(s.status),
                            isNew: DateTime.now().difference(r.createdAt).inDays < 30,
                            isAanraderOverride: _isAanrader(r, s),
                            onFavoriteTap: () async {
                              s.favorite = !s.favorite;
                              await _persistUser();
                            },
                            onBeenTap: () async {
                              s.status = s.status == VisitStatus.been
                                  ? VisitStatus.none
                                  : VisitStatus.been;
                              await _persistUser();
                            },
                            onWantToGoTap: () async {
                              s.status = s.status == VisitStatus.wantToGo
                                  ? VisitStatus.none
                                  : VisitStatus.wantToGo;
                              await _persistUser();
                            },
                            onTap: () async {
                              await _fetchPlaceOnDemand(r);
                              final updated = all.firstWhere((x) => x.id == r.id, orElse: () => r);
                              if (!context.mounted) return;
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => RestaurantDetailPage(
                                    restaurant: updated,
                                    state: s,
                                    onChanged: _persistUser,
                                    allRestaurants: all,
                                    resolveState: stateFor,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                      childCount: results.length,
                    ),
                  ),
                ),
          // ── Transparante opvulling onderaan ──
          const SliverFillRemaining(
            hasScrollBody: false,
            fillOverscroll: false,
            child: SizedBox(),
          ),
          ],
        ),
        ),
      ),
        ],
      ),
    );
  }
}

// ── Stat badge widget ─────────────────────────────────────────────────────────

// ── Sorteer optie rij ─────────────────────────────────────────────────────────
class _SorteerOptieRij extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SorteerOptieRij({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? _gold : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _gold : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? _navyDark : Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (selected)
              const Icon(Icons.check_circle_rounded, size: 20, color: _navyDark),
          ],
        ),
      ),
    );
  }
}

// ── Sheet Chip (voor in filtersheet, met emoji) ────────────────────────────
class _SheetChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SheetChip({required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isActive ? _gold : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isActive ? _gold : Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(
              color: isActive ? _navy : Colors.white,
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            )),
            if (isActive) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_rounded, size: 14, color: _navy),
            ],
          ],
        ),
      ),
    );
  }
}
// ── Restaurant kaart widget ───────────────────────────────────────────────────
class _RestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  final UserState state;
  final Color statusColor;
  final String statusLabel;
  final bool isNew;
  final bool isAanraderOverride;
  final VoidCallback onFavoriteTap;
  final VoidCallback onTap;
  final VoidCallback onBeenTap;
  final VoidCallback onWantToGoTap;

  const _RestaurantCard({
    required this.restaurant,
    required this.state,
    required this.statusColor,
    required this.statusLabel,
    required this.isNew,
    required this.isAanraderOverride,
    required this.onFavoriteTap,
    required this.onTap,
    required this.onBeenTap,
    required this.onWantToGoTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    final s = state;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Foto-balk
            Container(
              height: 110,
              decoration: const BoxDecoration(
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
                color: Color(0xFF2D2F6B),
              ),
              child: Stack(
                children: [
                  // Google foto of navy fallback met naam
                  if (r.photoName != null)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16)),
                        child: CachedNetworkImage(
                          imageUrl: PlacesService.photoUrl(r.photoName!),
                          fit: BoxFit.cover,
                          placeholder: (context, url) => const ColoredBox(color: Color(0xFF2D2F6B)),
                          errorWidget: (context, url, error) => _NavyFallback(name: r.name),
                        ),
                      ),
                    )
                  else
                    Positioned.fill(child: _NavyFallback(name: r.name)),
                ],
              ),
            ),

            // Inhoud
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.name,
                          style: const TextStyle(
                            color: _navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Nog proeven (heideRoze) — links
                          GestureDetector(
                            onTap: onWantToGoTap,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: s.status == VisitStatus.wantToGo
                                    ? _heideRoze.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                s.status == VisitStatus.wantToGo
                                    ? Icons.bookmark_rounded
                                    : Icons.bookmark_border_rounded,
                                color: s.status == VisitStatus.wantToGo
                                    ? _heideRoze
                                    : _navy.withValues(alpha: 0.3),
                                size: 24,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          // Al geproefd (gold) — rechts
                          GestureDetector(
                            onTap: onBeenTap,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: s.status == VisitStatus.been
                                    ? _gold.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                s.status == VisitStatus.been
                                    ? Icons.check_circle_rounded
                                    : Icons.check_circle_outline_rounded,
                                color: s.status == VisitStatus.been
                                    ? _gold
                                    : _navy.withValues(alpha: 0.3),
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.location_on,
                          size: 12, color: _navy.withValues(alpha: 0.45)),
                      const SizedBox(width: 3),
                      Text(
                        r.wijk.isNotEmpty
                            ? '${r.city} · ${r.wijk}'
                            : r.city,
                        style: TextStyle(
                          color: _navy.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                      if (r.googleReviewCount != null && r.googleReviewCount! > 0) ...[
                        Text(
                          '  (${r.googleReviewCount} reviews)',
                          style: TextStyle(
                            color: _navy.withValues(alpha: 0.38),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children:
                        r.cuisines.map((c) => _CuisineChip(label: c)).toList(),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Rating + prijs
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (r.googleRating != null) ...[ 
                            Text(
                              r.googleRating!.toStringAsFixed(1),
                              style: const TextStyle(
                                color: _navy,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            ...List.generate(5, (i) {
                              final full = i < r.googleRating!.floor();
                              final half = !full && i < r.googleRating!;
                              return Icon(
                                half ? Icons.star_half_rounded : Icons.star_rounded,
                                size: 13,
                                color: full || half ? _gold : Colors.grey.shade300,
                              );
                            }),
                            const SizedBox(width: 6),
                          ],
                          if (r.prijs != null)
                            Text(
                              r.prijs!,
                              style: TextStyle(
                                color: _navy.withValues(alpha: 0.55),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Bekijk details',
                            style: TextStyle(
                              color: _orange,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.arrow_forward_ios,
                              size: 11, color: _orange),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}


class _NavyFallback extends StatelessWidget {
  final String name;
  const _NavyFallback({required this.name});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Container(
        color: _navy,
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _CuisineChip extends StatelessWidget {
  final String label;
  const _CuisineChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _lavender.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _lavender.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _navy,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Aanbevolen kaart widget ───────────────────────────────────────────────────
// ── Detail pagina ─────────────────────────────────────────────────────────────
class RestaurantDetailPage extends StatefulWidget {
  final Restaurant restaurant;
  final UserState state;
  final Future<void> Function() onChanged;
  final List<Restaurant> allRestaurants;
  final UserState Function(String)? resolveState;

  const RestaurantDetailPage({
    super.key,
    required this.restaurant,
    required this.state,
    required this.onChanged,
    this.allRestaurants = const [],
    this.resolveState,
  });

  @override
  State<RestaurantDetailPage> createState() => _RestaurantDetailPageState();
}

class _RestaurantDetailPageState extends State<RestaurantDetailPage> {
  late final TextEditingController _note;
  bool _noteChanged = false;
  bool _noteSaved = false;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.state.note);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.restaurant;
    final s = widget.state;
    final similar = () {
      final rCuisines = r.cuisines.toSet();
      final candidates = widget.allRestaurants.where((o) {
        if (o.id == r.id) return false;
        if (widget.resolveState!(o.id).status == VisitStatus.been) return false;
        return o.cuisines.any((c) => rCuisines.contains(c));
      }).toList();
      // Score: cuisine overlap + zelfde wijk + google rating
      double score(Restaurant o) {
        final overlap = o.cuisines.where((c) => rCuisines.contains(c)).length;
        final wijkBonus = (o.wijk == r.wijk) ? 2.0 : 0.0;
        final ratingBonus = (o.googleRating ?? 3.5) * 0.5;
        return overlap * 3.0 + wijkBonus + ratingBonus;
      }
      candidates.sort((a, b) => score(b).compareTo(score(a)));
      return candidates.take(4).toList();
    }();

    return Scaffold(
      backgroundColor: _cream,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        title: Text(r.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Delen',
            onPressed: () {
              final mapsLink = 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('${r.name} ${r.city}')}';
              final text = 'Horeca Parel van het Zuiden gevonden: ${r.name}\n📍 ${r.address ?? r.city}\n\n$mapsLink';
              SharePlus.instance.share(ShareParams(text: text));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/image.png',
                fit: BoxFit.cover,
                errorBuilder: (_, err, stack) => Container(color: _cream),
              ),
            ),
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
          // Hero kleurblok / foto
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              height: 100,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_navyDark, _lavender],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (r.photoName != null)
                    CachedNetworkImage(
                      imageUrl: PlacesService.photoUrl(r.photoName!, maxWidth: 1200),
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const ColoredBox(color: Color(0xFF2D2F6B)),
                      errorWidget: (context, url, error) => const SizedBox.shrink(),
                    ),
                  // Gradient overlay voor leesbaarheid
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.1),
                          Colors.black.withValues(alpha: 0.55),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (r.photoName == null)
                          Icon(
                            _cuisineIcon(r.cuisines),
                            size: 36,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        if (r.photoName == null) const SizedBox(height: 6),
                        Text(
                          r.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(
                                  blurRadius: 6,
                                  color: Colors.black54,
                                  offset: Offset(0, 2))
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Info kaart
          _DetailCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(
                  icon: Icons.location_on,
                  label: 'Adres',
                  value: r.address ?? r.city,
                  onTap: () async {
                    final query = Uri.encodeComponent('${r.address ?? r.name} ${r.city}');
                    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
                const Divider(height: 16),
                _InfoRow(
                  icon: Icons.restaurant_menu,
                  label: 'Categorie',
                  value: r.cuisines.join(', '),
                ),
                if (r.prijs != null) ...[
                  const Divider(height: 16),
                  _InfoRow(
                    icon: Icons.euro_rounded,
                    label: 'Prijsklasse',
                    value: r.prijs!,
                  ),
                ],
                const Divider(height: 16),
                _InfoRow(
                  icon: Icons.child_care,
                  label: 'Speelhoek',
                  value: r.hasPlayCorner ? 'Ja ✓' : 'Nee',
                ),
                if (r.website != null && r.website!.isNotEmpty) ...[
                  const Divider(height: 16),
                  _InfoRow(
                    icon: Icons.language,
                    label: 'Website',
                    value: r.website!
                        .replaceFirst(RegExp(r'https?://'), ''),
                    onTap: () => _showWebsiteDialog(context, r.website!),
                  ),
                ],
              ],
            ),
          ),
          // Faciliteiten, sfeer, openVoor, menuOpties
          if (r.terras || r.honden || r.wifi || r.rolstoeltoegankelijk ||
              r.reserveren || r.openVoor.isNotEmpty ||
              r.menuOpties.isNotEmpty) ...[
            const SizedBox(height: 12),
            _DetailCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Faciliteiten icons
                  if (r.terras || r.honden || r.wifi ||
                      r.rolstoeltoegankelijk || r.reserveren) ...[
                    const Text('Faciliteiten',
                        style: TextStyle(
                            color: _navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        if (r.terras) _FaciliteitBadge(Icons.deck_rounded, 'Terras'),
                        if (r.honden) _FaciliteitBadge(Icons.pets_rounded, 'Honden'),
                        if (r.wifi) _FaciliteitBadge(Icons.wifi_rounded, 'Wifi'),
                        if (r.rolstoeltoegankelijk) _FaciliteitBadge(Icons.accessible_rounded, 'Rolstoel'),
                        if (r.reserveren) _FaciliteitBadge(Icons.event_seat_rounded, 'Reserveren'),
                      ],
                    ),
                    if (r.openVoor.isNotEmpty || r.menuOpties.isNotEmpty)
                      const Divider(height: 20),
                  ],
                  // Open voor badges
                  if (r.openVoor.isNotEmpty) ...[
                    const Text('Open voor',
                        style: TextStyle(
                            color: _navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: r.openVoor
                          .map((o) => _InfoBadge(o, _lavender))
                          .toList(),
                    ),
                    if (r.menuOpties.isNotEmpty)
                      const Divider(height: 20),
                  ],

                  // Menu opties chips (oranje licht)
                  if (r.menuOpties.isNotEmpty) ...[
                    const Text('Menu',
                        style: TextStyle(
                            color: _navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: r.menuOpties
                          .map((m) => _InfoBadge(m, _orange))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (r.verhaal != null) ...[
            const SizedBox(height: 12),
            Container(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: _cream,
                borderRadius: BorderRadius.circular(14),
                border: Border(
                  left: BorderSide(color: _heideRoze, width: 4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.edit_rounded, size: 13, color: _heideRoze),
                      const SizedBox(width: 5),
                      const Text(
                        'Bredase Bourgondiër',
                        style: TextStyle(
                          color: _heideRoze,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '"${r.verhaal!}"',
                    style: const TextStyle(
                      color: _navy,
                      fontStyle: FontStyle.italic,
                      fontSize: 14,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Reserveer knop
          if (r.reserveren && (r.reserveringUrl != null || r.website != null)) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.event_seat_rounded, size: 18),
                label: const Text('Reserveer', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                onPressed: () => _showWebsiteDialog(
                  context,
                  r.reserveringUrl ?? r.website!,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Openingstijden
          if (r.openingstijden.isNotEmpty) ...[
            _DetailCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Openingstijden',
                    style: TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Builder(builder: (context) {
                    const dayOrder = [
                      'ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'
                    ];
                    const dayNames = {
                      'ma': 'Maandag',
                      'di': 'Dinsdag',
                      'wo': 'Woensdag',
                      'do': 'Donderdag',
                      'vr': 'Vrijdag',
                      'za': 'Zaterdag',
                      'zo': 'Zondag',
                    };
                    final today =
                        dayOrder[DateTime.now().weekday - 1];
                    return Column(
                      children: dayOrder.map((day) {
                        final hours =
                            r.openingstijden[day] ?? 'Onbekend';
                        final isToday = day == today;
                        final isClosed = hours == 'Gesloten';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 90,
                                child: Text(
                                  dayNames[day]!,
                                  style: TextStyle(
                                    color: isToday
                                        ? _gold
                                        : _navy.withValues(alpha: 0.6),
                                    fontWeight: isToday
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Text(
                                hours,
                                style: TextStyle(
                                  color: isClosed
                                      ? _navy.withValues(alpha: 0.35)
                                      : (isToday ? _navy : _navy),
                                  fontWeight: isToday
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  fontSize: 13,
                                ),
                              ),
                              if (isToday && !isClosed) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _orange.withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Vandaag',
                                    style: TextStyle(
                                      color: _orange,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (r.menuUrl != null) ...[
            SizedBox(width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
                icon: const Icon(Icons.menu_book_rounded, size: 18),
                label: const Text('Bekijk menu', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                onPressed: () => _showWebsiteDialog(context, r.menuUrl!),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Ervaring kaart
          _DetailCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Jouw ervaring',
                  style: TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StatusButton(
                      label: 'Nog proeven',
                      icon: Icons.bookmark_border,
                      isSelected: s.status == VisitStatus.wantToGo,
                      color: _heideRoze,
                      onTap: () async {
                        setState(() => s.status =
                            s.status == VisitStatus.wantToGo
                                ? VisitStatus.none
                                : VisitStatus.wantToGo);
                        await widget.onChanged();
                      },
                    ),
                    const SizedBox(width: 8),
                    _StatusButton(
                      label: 'Al geproefd',
                      icon: Icons.check_circle_outline,
                      isSelected: s.status == VisitStatus.been,
                      color: _gold,
                      onTap: () async {
                        setState(() => s.status =
                            s.status == VisitStatus.been
                                ? VisitStatus.none
                                : VisitStatus.been);
                        await widget.onChanged();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Jouw rating',
                  style: TextStyle(
                      color: _navy, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(5, (i) {
                    final value = i + 1;
                    final filled = (s.rating ?? 0) >= value;
                    return GestureDetector(
                      onTap: () async {
                        setState(() => s.rating = value);
                        final messenger = ScaffoldMessenger.of(context);
                        await widget.onChanged();
                        if (!mounted) return;
                        if (value == 5) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Olé! Een echte parel gevonden!'),
                              backgroundColor: _gold,
                              duration: Duration(seconds: 3),
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _PearlIcon(
                          filled: filled,
                          color: filled ? _gold : _navy.withValues(alpha: 0.2),
                          size: 36,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _note,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notitie',
                    hintText: 'Bijv. "Speelhoek links achterin, kinderstoelen ok."',
                  ),
                  onChanged: (v) {
                    setState(() => _noteChanged = v != s.note);
                  },
                ),
                if (_noteChanged || _noteSaved) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _navy,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _noteSaved ? null : () async {
                        s.note = _note.text;
                        await widget.onChanged();
                        setState(() { _noteSaved = true; _noteChanged = false; });
                        await Future.delayed(const Duration(seconds: 2));
                        if (mounted) setState(() => _noteSaved = false);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _noteSaved ? Icons.check_circle_rounded : Icons.save_rounded,
                            size: 16,
                            color: _noteSaved ? _gold : Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _noteSaved ? 'Opgeslagen' : 'Notitie opslaan',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Vergelijkbare restaurants
          if (similar.isNotEmpty) ...[
            const SizedBox(height: 12),
            _DetailCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Misschien ook wat voor jou',
                    style: TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...similar.map((o) {
                    final oState = widget.resolveState!(o.id);
                    return GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => RestaurantDetailPage(
                          restaurant: o,
                          state: oState,
                          onChanged: widget.onChanged,
                          allRestaurants: widget.allRestaurants,
                          resolveState: widget.resolveState,
                        ),
                      )),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Icon(_cuisineIcon(o.cuisines), size: 18, color: _gold),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(o.name,
                                      style: const TextStyle(color: _navy, fontWeight: FontWeight.w700, fontSize: 13)),
                                  Text(
                                    [o.wijk, if (o.googleRating != null) '${o.googleRating!.toStringAsFixed(1)} ★'].join(' · '),
                                    style: TextStyle(color: _navy.withValues(alpha: 0.5), fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, size: 18, color: _gold),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
          ),
          ],
        ),
        ),
    );
  }
}

class _FaciliteitBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FaciliteitBadge(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _navy.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _navy.withValues(alpha: 0.15)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: _navy),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: _navy, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _InfoBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _InfoBadge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

class _DetailCard extends StatelessWidget {
  final Widget child;
  const _DetailCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _InfoRow(
      {required this.icon, required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _gold),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: const TextStyle(color: _navy, fontWeight: FontWeight.w600),
        ),
        Expanded(
          child: onTap != null
              ? GestureDetector(
                  onTap: onTap,
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: _gold,
                      decoration: TextDecoration.underline,
                      decorationColor: _gold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              : Text(
                  value,
                  style: TextStyle(color: _navy.withValues(alpha: 0.75)),
                ),
        ),
      ],
    );
  }
}

class _StatusButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _StatusButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color : color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? Colors.white : color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Stel een restaurant voor pagina ──────────────────────────────────────────
class StelVoorPage extends StatefulWidget {
  const StelVoorPage({super.key});

  @override
  State<StelVoorPage> createState() => _StelVoorPageState();
}

class _StelVoorPageState extends State<StelVoorPage> {
  final _foutController = TextEditingController();
  final _suggestieController = TextEditingController();

  @override
  void dispose() {
    _foutController.dispose();
    _suggestieController.dispose();
    super.dispose();
  }

  Future<void> _stuurMail(String onderwerp, String tekst) async {
    final subject = Uri.encodeComponent(onderwerp);
    final body = Uri.encodeComponent(tekst);
    final uri = Uri.parse('mailto:horecaparelsvanhetzuiden@gmail.com?subject=$subject&body=$body');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kan geen e-mail app openen')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Neem contact op', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sectie 1: Suggestie (eerst)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _gold, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lightbulb_outline_rounded, color: _gold, size: 20),
                          SizedBox(width: 8),
                          Text('Ik heb een suggestie of feedback',
                              style: TextStyle(color: _gold, fontWeight: FontWeight.w700, fontSize: 15)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text('Mis je een restaurant, of heb je een idee voor de app?',
                          style: TextStyle(color: _navy, fontSize: 12)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _suggestieController,
                        maxLines: 4,
                        style: const TextStyle(color: _navy, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Jouw suggestie of feedback...',
                          hintStyle: TextStyle(color: _navy.withValues(alpha: 0.35), fontSize: 13),
                          filled: true,
                          fillColor: _cream,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: _navy.withValues(alpha: 0.18)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: _navy.withValues(alpha: 0.18)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: _gold, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                          label: const Text('Stuur suggestie', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          style: FilledButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.white),
                          onPressed: () {
                            final t = _suggestieController.text.trim();
                            if (t.isEmpty) return;
                            _stuurMail('Suggestie HPvhZ', t);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Sectie 2: Suggestie/feedback
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _heideRoze, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.error_outline_rounded, color: _heideRoze, size: 20),
                          SizedBox(width: 8),
                          Text('Ej, dit klopt niet!',
                              style: TextStyle(color: _heideRoze, fontWeight: FontWeight.w700, fontSize: 15)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text('Restaurant gesloten, fout adres, verkeerde info?',
                          style: TextStyle(color: _navy, fontSize: 12)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _foutController,
                        maxLines: 4,
                        style: const TextStyle(color: _navy, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Beschrijf wat er niet klopt...',
                          hintStyle: TextStyle(color: _navy.withValues(alpha: 0.35), fontSize: 13),
                          filled: true,
                          fillColor: _cream,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: _navy.withValues(alpha: 0.18)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: _navy.withValues(alpha: 0.18)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: _heideRoze, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                          label: const Text('Stuur melding', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          style: FilledButton.styleFrom(backgroundColor: _heideRoze, foregroundColor: Colors.white),
                          onPressed: () {
                            final t = _foutController.text.trim();
                            if (t.isEmpty) return;
                            _stuurMail('Foutmelding HPvhZ', t);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
    );
  }
}


class StatisticsPage extends StatelessWidget {
  final List<Restaurant> all;
  final Map<String, UserState> user;

  const StatisticsPage({super.key, required this.all, required this.user});

  UserState _stateFor(String id) => user[id] ?? UserState();

  String _favoriteCuisine() {
    final counts = <String, int>{};
    for (final r in all) {
      if (_stateFor(r.id).status == VisitStatus.been) {
        for (final c in r.cuisines) {
          counts[c] = (counts[c] ?? 0) + 1;
        }
      }
    }
    if (counts.isEmpty) return '–';
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  Map<int, List<Restaurant>> _jaarboek() {
    final now = DateTime.now();
    final map = <int, List<Restaurant>>{};
    for (final r in all) {
      if (_stateFor(r.id).status == VisitStatus.been &&
          r.createdAt.year == now.year) {
        map.putIfAbsent(now.year, () => []).add(r);
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final total = all.length;
    final beenCount = user.values.where((s) => s.status == VisitStatus.been).length;
    final wantCount = user.values.where((s) => s.status == VisitStatus.wantToGo).length;
    final favCuisine = _favoriteCuisine();
    final jaarboek = _jaarboek();
    final pct = total == 0 ? 0.0 : beenCount / total;
    final now = DateTime.now();
    final toonJaarboek = now.month >= 11;

    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        title: const Text('Jouw Bredase avontuur'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 4),

          // ── Overzichtskaarten ──
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.restaurant,
                  label: 'Totaal',
                  value: '$total',
                  color: _navy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  icon: Icons.check_circle_outline,
                  label: 'Bezocht',
                  value: '$beenCount',
                  color: _heideRoze,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  icon: Icons.bookmark_border,
                  label: 'Nog proeven',
                  value: '$wantCount',
                  color: _gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Voortgangsbalk ──
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Voortgang',
                      style: TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${(pct * 100).round()}%',
                      style: const TextStyle(
                        color: _orange,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 10,
                    backgroundColor: _lavender.withValues(alpha: 0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(_orange),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$beenCount van $total restaurants bezocht',
                  style: TextStyle(
                    color: _navy.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Favoriete keuken ──
          _SectionCard(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.restaurant_menu, color: _orange, size: 22),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Favoriete categorie',
                      style: TextStyle(
                        color: _navy.withValues(alpha: 0.55),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      favCuisine,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Jaarboek (alleen zichtbaar 1 nov – 31 dec) ──
          if (toonJaarboek) ...[
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                'Jouw jaar in de Baronie',
                style: TextStyle(
                  color: _navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
            ),

            if (jaarboek.isEmpty)
              _SectionCard(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Nog geen restaurants bezocht dit jaar',
                      style: TextStyle(color: _navy.withValues(alpha: 0.45)),
                    ),
                  ),
                ),
              )
            else
              for (final entry in jaarboek.entries) ...[
                _YearSection(
                  year: entry.key,
                  restaurants: entry.value,
                  user: user,
                ),
                const SizedBox(height: 12),
              ],

            const SizedBox(height: 8),
          ],

          // ── Badges ──
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'Jouw badges',
              style: TextStyle(
                color: _navy,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
          ),
          _SectionCard(
            child: Wrap(
              spacing: 16,
              runSpacing: 20,
              children: [
                for (final badge in _allBadges)
                  _BadgeTile(
                    badge: badge,
                    earned: badge.isEarned(all, user),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  final _AppBadge badge;
  final bool earned;

  const _BadgeTile({required this.badge, required this.earned});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: earned ? _gold.withValues(alpha: 0.15) : _navy.withValues(alpha: 0.06),
              shape: BoxShape.circle,
              border: Border.all(
                color: earned ? _gold : _navy.withValues(alpha: 0.2),
                width: 2,
              ),
            ),
            child: Icon(
              badge.icon,
              size: 26,
              color: earned ? _gold : _navy.withValues(alpha: 0.28),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            badge.name,
            style: TextStyle(
              color: earned ? _navy : _navy.withValues(alpha: 0.28),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (earned)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.check_circle_rounded, size: 12, color: _gold),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.07),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: _navy.withValues(alpha: 0.55),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.07),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _YearSection extends StatelessWidget {
  final int year;
  final List<Restaurant> restaurants;
  final Map<String, UserState> user;

  const _YearSection({
    required this.year,
    required this.restaurants,
    required this.user,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.07),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Jaar header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _navy,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: _gold, size: 14),
                const SizedBox(width: 8),
                Text(
                  '$year',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${restaurants.length} restaurant${restaurants.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Restaurant rijen
          for (int i = 0; i < restaurants.length; i++) ...[
            if (i > 0) Divider(height: 1, color: _cream),
            _JaarboekRow(restaurant: restaurants[i], user: user),
          ],
        ],
      ),
    );
  }
}

class _JaarboekRow extends StatelessWidget {
  final Restaurant restaurant;
  final Map<String, UserState> user;

  const _JaarboekRow({required this.restaurant, required this.user});

  @override
  Widget build(BuildContext context) {
    final r = restaurant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            _cuisineIcon(r.cuisines),
            size: 22,
            color: _navy.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 12),
          // Naam + keuken
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.name,
                  style: const TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  r.cuisines.join(', '),
                  style: TextStyle(
                    color: _navy.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

// ── Website popup helper ──────────────────────────────────────────────────────
void _showWebsiteDialog(BuildContext context, String url) {
  final displayUrl = url.replaceFirst(RegExp(r'https?://'), '');
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.language, color: _orange, size: 22),
          SizedBox(width: 8),
          Text('Website', style: TextStyle(color: _navy, fontSize: 18)),
        ],
      ),
      content: Text(
        displayUrl,
        style: const TextStyle(color: _navy, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('Annuleren',
              style: TextStyle(color: _navy.withValues(alpha: 0.5))),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Openen'),
          onPressed: () async {
            Navigator.of(ctx).pop();
            final uri = Uri.parse(
                url.startsWith('http') ? url : 'https://$url');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        ),
      ],
    ),
  );
}

// ── Sticky filterbar delegate ─────────────────────────────────────────────────
// ── Geweest Pagina ────────────────────────────────────────────────────────────
class _GeweestPage extends StatelessWidget {
  final List<Restaurant> all;
  final Map<String, UserState> user;
  final Future<void> Function() onChanged;
  const _GeweestPage({required this.all, required this.user, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final beenList = all.where((r) => (user[r.id]?.status ?? VisitStatus.none) == VisitStatus.been).toList()
      ..sort((a, b) => (user[b.id]?.rating ?? 0).compareTo(user[a.id]?.rating ?? 0));
    final beenCount = beenList.length;

    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: Text('Al geproefd ($beenCount)', style: const TextStyle(fontWeight: FontWeight.w800)),
        elevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          // ── Badges ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Jouw badges',
                    style: TextStyle(color: _navy, fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.75,
                    ),
                    itemCount: _allBadges.length,
                    itemBuilder: (context, index) {
                      final badge = _allBadges[index];
                      final earned = badge.isEarned(all, user);
                      return Tooltip(
                        message: badge.description,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                          decoration: BoxDecoration(
                            color: earned ? _navy : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: earned ? _gold : _navy.withValues(alpha: 0.12),
                              width: earned ? 2 : 1,
                            ),
                            boxShadow: earned ? [
                              BoxShadow(color: _gold.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))
                            ] : [],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(badge.icon, size: 26, color: earned ? _gold : _navy.withValues(alpha: 0.2)),
                              const SizedBox(height: 5),
                              Text(
                                badge.name,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: earned ? Colors.white : _navy.withValues(alpha: 0.3),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (earned) ...[
                                const SizedBox(height: 4),
                                const Icon(Icons.check_circle_rounded, size: 10, color: _gold),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Bezochte restaurants',
                    style: TextStyle(color: _navy, fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
          // ── Restaurant lijst ──
          beenList.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'Nog nergens geweest — op pad!',
                        style: TextStyle(color: _navy.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final r = beenList[i];
                      final s = user[r.id] ?? UserState();
                      return Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, i == beenList.length - 1 ? 32 : 8),
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => RestaurantDetailPage(
                              restaurant: r,
                              state: s,
                              onChanged: onChanged,
                              allRestaurants: all,
                              resolveState: (id) => user[id] ?? UserState(),
                            ),
                          )),
                          child: Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                              leading: CircleAvatar(
                                backgroundColor: _gold,
                                child: Icon(_cuisineIcon(r.cuisines), color: Colors.white, size: 20),
                              ),
                              title: Text(r.name, style: const TextStyle(color: _navy, fontWeight: FontWeight.w700, fontSize: 14)),
                              subtitle: Text('${r.wijk} · ${r.cuisines.take(2).join(', ')}',
                                  style: TextStyle(color: _navy.withValues(alpha: 0.5), fontSize: 12)),
                              trailing: s.rating != null
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: List.generate(5, (star) => _PearlIcon(
                                        filled: star < s.rating!,
                                        color: _gold,
                                        size: 16,
                                      )),
                                    )
                                  : const Icon(Icons.chevron_right_rounded, color: _gold, size: 20),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: beenList.length,
                  ),
                ),
        ],
      ),
    );
  }
}

// ── Wil Ik Heen Pagina ────────────────────────────────────────────────────────
class _WilIkHeenPage extends StatelessWidget {
  final List<Restaurant> all;
  final Map<String, UserState> user;
  final Future<void> Function() onChanged;
  const _WilIkHeenPage({required this.all, required this.user, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final wantList = all.where((r) => (user[r.id]?.status ?? VisitStatus.none) == VisitStatus.wantToGo).toList();
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Nog proeven', style: TextStyle(fontWeight: FontWeight.w800)),
        elevation: 0,
      ),
      body: wantList.isEmpty
          ? const Center(child: Text('Nog niets op je lijstje — voeg restaurants toe!', style: TextStyle(color: _navy)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: wantList.length,
              itemBuilder: (context, i) {
                final r = wantList[i];
                final s = user[r.id] ?? UserState();
                final openVoorStr = r.openVoor.isNotEmpty ? r.openVoor.take(2).join(' · ') : '';
                final cuisineStr = r.cuisines.isNotEmpty ? r.cuisines.first : '';
                final subtitle = [
                  if (r.wijk.isNotEmpty) r.wijk,
                  if (openVoorStr.isNotEmpty) openVoorStr,
                  if (cuisineStr.isNotEmpty) cuisineStr,
                ].join(' · ');
                return GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RestaurantDetailPage(
                      restaurant: r,
                      state: s,
                      onChanged: onChanged,
                      allRestaurants: all,
                      resolveState: (id) => user[id] ?? UserState(),
                    ),
                  )),
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      leading: CircleAvatar(
                        backgroundColor: _heideRoze,
                        child: Icon(_cuisineIcon(r.cuisines), color: Colors.white, size: 20),
                      ),
                      title: Text(r.name, style: const TextStyle(color: _navy, fontWeight: FontWeight.w700, fontSize: 14)),
                      subtitle: Text(subtitle, style: TextStyle(color: _navy.withValues(alpha: 0.5), fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: _gold, size: 20),
                    ),
                  ),
                );
              },
            ),
    );
  }
}


// ── Parel in de spotlight ─────────────────────────────────────────────────────
class _SpotlightPage extends StatefulWidget {
  const _SpotlightPage();

  @override
  State<_SpotlightPage> createState() => _SpotlightPageState();
}

class _SpotlightPageState extends State<_SpotlightPage> {
  final _naamController = TextEditingController();
  final _contactController = TextEditingController();
  final _berichtController = TextEditingController();
  bool _verzonden = false;

  @override
  void dispose() {
    _naamController.dispose();
    _contactController.dispose();
    _berichtController.dispose();
    super.dispose();
  }

  Future<void> _verstuur() async {
    final naam = _naamController.text.trim();
    final contact = _contactController.text.trim();
    final bericht = _berichtController.text.trim();
    if (naam.isEmpty || contact.isEmpty) return;

    final onderwerp = Uri.encodeComponent('Parel in de spotlight: $naam');
    final body = Uri.encodeComponent(
      'Naam etablissement: $naam\n'
      'Contact (e-mail/telefoon): $contact\n'
      '\nBericht:\n$bericht',
    );
    final uri = Uri.parse('mailto:horecaparelsvanhetzuiden@gmail.com?subject=$onderwerp&body=$body');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      setState(() => _verzonden = true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Parel in de spotlight', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
        child: _verzonden
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  const Text('✦', style: TextStyle(fontSize: 48, color: _gold)),
                  const SizedBox(height: 16),
                  const Text(
                    'Bedankt!',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _navy),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'We nemen zo snel mogelijk contact met je op.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 15),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _navy,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _gold, width: 1.5),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('✦  Jouw etablissement in de spotlight', style: TextStyle(color: _gold, fontSize: 16, fontWeight: FontWeight.w700)),
                        SizedBox(height: 8),
                        Text(
                          'Wil je dat jouw restaurant extra zichtbaar is in Horeca Parels van het Zuiden? '
                          'Neem contact op — dan kijken we samen wat mogelijk is.',
                          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _navy.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Naam etablissement',
                            style: TextStyle(fontWeight: FontWeight.w700, color: _navy, fontSize: 14)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _naamController,
                          style: const TextStyle(color: _navy, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Naam van je zaak',
                            hintStyle: TextStyle(color: _navy.withValues(alpha: 0.35), fontSize: 13),
                            filled: true,
                            fillColor: _cream,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: _navy.withValues(alpha: 0.18)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: _navy.withValues(alpha: 0.18)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _gold, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text('E-mailadres of telefoonnummer',
                            style: TextStyle(fontWeight: FontWeight.w700, color: _navy, fontSize: 14)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _contactController,
                          style: const TextStyle(color: _navy, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'bijv. info@restaurant.nl',
                            hintStyle: TextStyle(color: _navy.withValues(alpha: 0.35), fontSize: 13),
                            filled: true,
                            fillColor: _cream,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: _navy.withValues(alpha: 0.18)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: _navy.withValues(alpha: 0.18)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _gold, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text('Bericht (optioneel)',
                            style: TextStyle(fontWeight: FontWeight.w700, color: _navy, fontSize: 14)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _berichtController,
                          maxLines: 4,
                          style: const TextStyle(color: _navy, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Vertel iets over je zaak of wat je in gedachten hebt...',
                            hintStyle: TextStyle(color: _navy.withValues(alpha: 0.35), fontSize: 13),
                            filled: true,
                            fillColor: _cream,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: _navy.withValues(alpha: 0.18)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: _navy.withValues(alpha: 0.18)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _gold, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _verstuur,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Stuur bericht', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }
}

// ── In het licht van de parel ───────────────────────────────────────────────
class _InHetLichtPage extends StatelessWidget {
  const _InHetLichtPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Over Horeca Parels van het Zuiden (HPvhZ)',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Intro blok
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _navy,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('✦  Horeca Parels van het Zuiden',
                          style: TextStyle(color: _gold, fontSize: 16, fontWeight: FontWeight.w800)),
                      SizedBox(height: 10),
                      Text(
                        'Een persoonlijke horecagids voor Breda. Geen algoritmes, geen advertenties — alleen echte parels, uitgekozen door een Bredase Bourgondiër.',
                        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                _InfoBlok(
                  icoon: Icons.help_outline_rounded,
                  kleur: _gold,
                  titel: 'Waarom heb ik deze app gebouwd?',
                  tekst: 'Deze Bredase bourgondiër twijfelt niet graag — knopen doorhakken, ook als het gaat om een gezellig avondje tafelen. Nieuwe restaurants ontdekken, lijstjes bijhouden en niets vergeten: een extern geheugen was geen luxe maar een must. Het idee ontstond tijdens een lunch met een mede-bourgondiër — hup NAC — en de rest is app-geschiedenis.',
                ),
                const SizedBox(height: 16),

                _InfoBlok(
                  icoon: Icons.place_rounded,
                  kleur: _gold,
                  titel: 'Wat zit erin?',
                  tekst: "150+ horecaparels in Breda. Van die bruine kroeg in het Ginneken, tot het fine dining restaurant in het centrum. Met echte foto's, openingstijden, Google-ratings en verhalen die je in geen enkele reisgids vindt.",
                ),
                const SizedBox(height: 16),

                _InfoBlok(
                  icoon: Icons.touch_app_rounded,
                  kleur: _gold,
                  titel: 'Hoe werkt het?',
                  tekst: 'Tikken, bewaren, vergeten dat je het bewaard had, toch terugvinden net wanneer je het nodig hebt. Je vinkt af wat je geproefd hebt, slaat op wat je nog wil proberen, en geeft restaurants een eigen sterrenscore.',
                ),
                const SizedBox(height: 16),

                _InfoBlok(
                  icoon: Icons.star_rounded,
                  kleur: _gold,
                  titel: 'Wat betekent de sterrenscore?',
                  tekst: 'De sterrenscore is je eigen beoordeling — van 1 tot 5 sterren. Hoe meer je beoordeelt, hoe slimmer de "Parels die bij jou passen" strip wordt. Google-ratings staan er los naast vermeld.',
                ),
                const SizedBox(height: 16),

                _InfoBlok(
                  icoon: Icons.euro_rounded,
                  kleur: _gold,
                  titel: 'Wat betekenen de €-tekentjes?',
                  tekst: '€ = onder de €15 per persoon\n€€ = €15 – €30\n€€€ = €30 – €50\n€€€€ = boven de €50',
                ),
                const SizedBox(height: 24),

                // Ko-fi blok
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _gold, width: 1.5),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Vind je de app leuk?',
                        style: TextStyle(color: _navy, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const SizedBox(height: 14),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final uri = Uri.parse('https://ko-fi.com/horecaparelsvanhetzuiden');
                          if (await canLaunchUrl(uri)) {
                            launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: const Icon(Icons.coffee_rounded),
                        label: const Text('Trakteer op Ko-fi'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _gold,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          textStyle: const TextStyle(fontWeight: FontWeight.w800),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
    );
  }
}


class _PearlIcon extends StatelessWidget {
  final bool filled;
  final Color color;
  final double size;

  const _PearlIcon({
    required this.filled,
    required this.color,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PearlPainter(filled: filled, color: color),
      ),
    );
  }
}

class _PearlPainter extends CustomPainter {
  final bool filled;
  final Color color;

  const _PearlPainter({required this.filled, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 * 0.88;
    final paint = Paint()
      ..color = color
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..isAntiAlias = true;

    // Hoofdcirkel
    canvas.drawCircle(center, radius, paint);

    // Glinstering — alleen zichtbaar als filled of als outline kleur helder genoeg
    if (filled) {
      final shinePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.07
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;

      // Groot boogje linksboven
      final path1 = Path();
      path1.addArc(
        Rect.fromCircle(
          center: Offset(center.dx - radius * 0.22, center.dy - radius * 0.28),
          radius: radius * 0.32,
        ),
        -2.4,
        1.4,
      );
      canvas.drawPath(path1, shinePaint);

      // Klein stipje rechtsboven
      final dotPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawCircle(
        Offset(center.dx + radius * 0.42, center.dy - radius * 0.38),
        size.width * 0.055,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_PearlPainter old) =>
      old.filled != filled || old.color != color;
}

class _InfoBlok extends StatelessWidget {
  final IconData icoon;
  final Color kleur;
  final String titel;
  final String tekst;

  const _InfoBlok({
    required this.icoon,
    required this.kleur,
    required this.titel,
    required this.tekst,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _navy.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kleur.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icoon, color: kleur, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titel,
                    style: const TextStyle(
                        color: _navy, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                Text(tekst,
                    style: TextStyle(
                        color: _navy.withValues(alpha: 0.75),
                        fontSize: 13,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Privacy Policy pagina ─────────────────────────────────────────────────────

// ── Herbruikbare image.png achtergrond ───────────────────────────────────────
class _ImageAchtergrond extends StatelessWidget {
  final Widget child;
  final double overlayOpacity;
  const _ImageAchtergrond({required this.child, this.overlayOpacity = 0.55});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/image.png',
          fit: BoxFit.cover,
          errorBuilder: (_, err, stack) => Container(color: _navyDark),
        ),
        Container(color: Colors.black.withValues(alpha: overlayOpacity)),
        child,
      ],
    );
  }
}

// ── Feedback / Ko-fi pagina ───────────────────────────────────────────────────
class _FeedbackPage extends StatelessWidget {
  const _FeedbackPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Blij met deze app?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                const _InfoBlok(
                  icoon: Icons.tips_and_updates_rounded,
                  kleur: _gold,
                  titel: 'Help mee de app verbeteren',
                  tekst: 'De app wordt continu verbeterd dankzij jullie input. Mis je een restaurant, klopt er iets niet, of heb je een suggestie? Ik hoor het graag en voer wijzigingen met plezier door.',
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _navy.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Trakteer de Bourgondiër',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _navy,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final uri = Uri.parse('https://ko-fi.com/horecaparelsvanhetzuiden');
                            if (await canLaunchUrl(uri)) {
                              launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          icon: const Icon(Icons.coffee_rounded),
                          label: const Text(
                            'Trakteer op Ko-fi',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _gold,
                            foregroundColor: _navyDark,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
    );
  }
}

// ── Privacybeleid ───────────────────────────────────────────────────────────
class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Privacybeleid', style: TextStyle(fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PrivacySection(
              titel: 'Horeca Parels van het Zuiden',
              inhoud: 'Versie 1.0 · Ingangsdatum: april 2026\n\n'
                  'Deze app is gemaakt door een onafhankelijke Bredase ontwikkelaar, '
                  'uit liefde voor de Bredase horeca. Jouw privacy is daarbij belangrijk. '
                  'Dit beleid legt uit welke gegevens we opslaan en waarom.',
            ),
            const SizedBox(height: 20),
            _PrivacySection(
              titel: '1. Welke gegevens slaan we op?',
              inhoud: 'De app slaat de volgende gegevens op — uitsluitend op jouw eigen apparaat:\n\n'
                  '• Jouw beoordelingen (1–5 parels) per restaurant\n'
                  '• Je persoonlijke notities per restaurant\n'
                  '• Je lijstjes: "Nog proeven" en "Geproefd"\n'
                  '• Jaarboek-gegevens (welke restaurants je hebt bezocht)\n\n'
                  'Deze gegevens verlaten jouw telefoon niet. Ze worden niet '
                  'doorgestuurd naar servers, niet verkocht en niet gedeeld met derden.',
            ),
            const SizedBox(height: 20),
            _PrivacySection(
              titel: '2. Google Places API',
              inhoud: 'De app maakt gebruik van de Google Places API om restaurantinformatie '
                  'op te halen, zoals namen, adressen, openingstijden, foto\'s en beoordelingen. '
                  'Hierbij wordt geen persoonlijke informatie van jou gedeeld met Google.\n\n'
                  'Google\'s eigen privacybeleid is van toepassing op het gebruik van hun diensten: '
                  'https://policies.google.com/privacy',
            ),
            const SizedBox(height: 20),
            _PrivacySection(
              titel: '3. Geen account, geen tracking',
              inhoud: 'De app heeft geen loginscherm en vereist geen account. '
                  'We houden geen gebruiksstatistieken bij, plaatsen geen advertenties '
                  'en gebruiken geen tracking-software zoals Google Analytics of Firebase.',
            ),
            const SizedBox(height: 20),
            _PrivacySection(
              titel: '4. Opslag op je apparaat',
              inhoud: 'Alle persoonlijke gegevens worden lokaal opgeslagen via '
                  'SharedPreferences — een standaard opslagmechanisme op Android en iOS. '
                  'Deze gegevens worden verwijderd wanneer je de app verwijdert.',
            ),
            const SizedBox(height: 20),
            _PrivacySection(
              titel: '5. Deelfunctie',
              inhoud: 'De app bevat een optionele deelfunctie waarmee je een restaurant '
                  'kunt delen via WhatsApp of andere apps. Dit deelt alleen de naam en '
                  'informatie van het betreffende restaurant — geen persoonlijke gegevens.',
            ),
            const SizedBox(height: 20),
            _PrivacySection(
              titel: '6. Kinderen',
              inhoud: 'De app is bedoeld voor algemeen gebruik en richt zich niet specifiek '
                  'op kinderen onder de 13 jaar. Er worden geen gegevens van minderjarigen '
                  'verzameld of verwerkt.',
            ),
            const SizedBox(height: 20),
            _PrivacySection(
              titel: '7. Wijzigingen',
              inhoud: 'Dit privacybeleid kan worden bijgewerkt bij nieuwe versies van de app. '
                  'Wijzigingen worden vermeld in de versienotities in de Google Play Store.',
            ),
            const SizedBox(height: 20),
            _PrivacySection(
              titel: '8. Contact',
              inhoud: 'Vragen over dit privacybeleid? Neem contact op via de app '
                  '("Parel in de spotlight" formulier) of via de Google Play Store pagina.',
            ),
            const SizedBox(height: 32),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _navy.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Samengevat: de app slaat jouw gegevens alleen lokaal op jouw telefoon op. '
                'Er wordt niets gedeeld, verkocht of bijgehouden. Gewoon een app voor Bredanaars, door een Bredanaar.',
                style: TextStyle(
                  color: _navy,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  final String titel;
  final String inhoud;
  const _PrivacySection({required this.titel, required this.inhoud});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titel, style: const TextStyle(
          color: _navy,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        )),
        const SizedBox(height: 8),
        Text(inhoud, style: TextStyle(
          color: _navy.withValues(alpha: 0.75),
          fontSize: 14,
          height: 1.6,
        )),
      ],
    );
  }
}

// ── Ontdek Kaartje widget ─────────────────────────────────────────────────────

// ── Profielgebaseerde carousel ────────────────────────────────────────────────
class _ProfielCarousel extends StatefulWidget {
  final List<Restaurant> all;
  final UserState Function(String) stateFor;
  final Future<void> Function() onChanged;

  const _ProfielCarousel({
    required this.all,
    required this.stateFor,
    required this.onChanged,
  });

  @override
  State<_ProfielCarousel> createState() => _ProfielCarouselState();
}

class _ProfielCarouselState extends State<_ProfielCarousel> {
  List<String> _profielSfeer = [];
  List<String> _profielOpenVoor = [];

  // Vaste mapping per profiel
  static const _profielLogica = {
    'Kroegtijger': {
      'cuisines': ['Café', 'Bruin café', 'Bier', 'Brouwerij', 'Eetcafé', 'Bar', 'Brasserie'],
      'sfeer': ['Bourgondisch', 'Gezellig'],
      'openVoor': ['Borrel'],
    },
    'Tafelgenoot': {
      'cuisines': ['Fine dining', 'Frans', 'Italiaans', 'Mediterraans', 'Brasserie', 'Bistro'],
      'sfeer': ['Romantisch', 'Klassiek', 'Intiem'],
      'openVoor': ['Diner'],
    },
    'Dagstarter': {
      'cuisines': ['Koffie', 'Ontbijt', 'Brunch', 'Bakkerij', 'Patisserie', 'Lunch', 'Tearoom'],
      'sfeer': ['Gezellig', 'Rustig', 'Hip & trendy', 'Huiselijk'],
      'openVoor': ['Ontbijt', 'Lunch'],
    },
    'Gezinsbourgondiër': {
      'cuisines': ['Brasserie', 'Nederlands', 'Café', 'Pizza'],
      'sfeer': ['Gezin', 'Gezellig'],
      'openVoor': ['Lunch', 'Diner'],
      'speelhoek': true,
    },
  };

  @override
  void initState() {
    super.initState();
    _laadProfiel();
  }

  Future<void> _laadProfiel() async {
    final prefs = await SharedPreferences.getInstance();
    final sfeer = prefs.getString('profiel_sfeer') ?? '';
    final open = prefs.getString('profiel_openVoor') ?? '';
    setState(() {
      _profielSfeer = sfeer.isEmpty ? [] : sfeer.split(',');
      _profielOpenVoor = open.isEmpty ? [] : open.split(',');
    });
  }

  List<Restaurant> _aanbevelingen() {
    // Gebruik sfeer/openVoor uit state voor filtering
    final onbezocht = widget.all.where((r) {
      final s = widget.stateFor(r.id);
      return s.status != VisitStatus.been;
    }).toList();

    if (onbezocht.isEmpty) return [];

    // Score per restaurant op basis van profiellogica
    double score(Restaurant r) {
      double s = 0;
      // Sfeer match
      for (final sfeer in _profielSfeer) {
        if (r.sfeer.contains(sfeer)) s += 3;
        // Check profiellogica
        for (final entry in _profielLogica.entries) {
          final logica = entry.value;
          final sfeers = logica['sfeer'] as List<String>;
          if (sfeers.contains(sfeer)) {
            final cuisines = logica['cuisines'] as List<String>;
            for (final c in r.cuisines) {
              if (cuisines.contains(c)) s += 2;
            }
          }
        }
      }
      // OpenVoor match
      for (final ov in _profielOpenVoor) {
        if (r.openVoor.contains(ov)) s += 2;
      }
      // Google rating boost
      s += (r.googleRating ?? 3.5) * 0.5;
      return s;
    }

    // Als geen profiel ingesteld: val terug op google rating
    if (_profielSfeer.isEmpty && _profielOpenVoor.isEmpty) {
      final metRating = onbezocht.where((r) => r.googleRating != null).toList()
        ..sort((a, b) => (b.googleRating ?? 0).compareTo(a.googleRating ?? 0));
      return metRating.take(4).toList();
    }

    onbezocht.sort((a, b) => score(b).compareTo(score(a)));
    return onbezocht.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final aanbevelingen = _aanbevelingen();
    if (aanbevelingen.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Text(
              'Parels die bij jou kunnen passen',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: aanbevelingen.length,
              separatorBuilder: (_, idx) => const SizedBox(width: 10),
              padding: const EdgeInsets.only(right: 16),
              itemBuilder: (context, i) {
                final r = aanbevelingen[i];
                final s = widget.stateFor(r.id);
                return GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RestaurantDetailPage(
                      restaurant: r,
                      state: s,
                      onChanged: widget.onChanged,
                      allRestaurants: widget.all,
                      resolveState: widget.stateFor,
                    ),
                  )),
                  child: Container(
                    width: 130,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: _navy,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Rating
                        if (r.googleRating != null)
                          Row(children: [
                            const Icon(Icons.star_rounded, size: 11, color: _gold),
                            const SizedBox(width: 2),
                            Text(r.googleRating!.toStringAsFixed(1),
                                style: const TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.w700)),
                          ]),
                        const SizedBox(height: 4),
                        Text(r.name,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, height: 1.2),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          [if (r.wijk.isNotEmpty) r.wijk, if (r.prijs != null) r.prijs!].join(' · '),
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Curated list pagina ───────────────────────────────────────────────────────
// ── Onboarding pagina ────────────────────────────────────────────────────────
class _OnboardingPage extends StatefulWidget {
  const _OnboardingPage();

  @override
  State<_OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<_OnboardingPage> {
  final Set<int> _selectedProfielen = {};

  static const _profielen = [
    (
      icon: Icons.sports_bar_rounded,
      naam: 'Kroegtijger',
      omschrijving: 'Borrel, bier & kroegsfeer',
      sfeer: 'Bourgondisch',
      openVoor: 'Borrel',
    ),
    (
      icon: Icons.table_restaurant_rounded,
      naam: 'Tafelgenoot',
      omschrijving: 'Lekker tafelen & een goed diner',
      sfeer: 'Romantisch',
      openVoor: 'Diner',
    ),
    (
      icon: Icons.wb_twilight_rounded,
      naam: 'Dagstarter',
      omschrijving: 'Ontbijt, brunch & koffie',
      sfeer: 'Gezellig',
      openVoor: 'Ontbijt',
    ),
    (
      icon: Icons.family_restroom_rounded,
      naam: 'Gezinsbourgondiër',
      omschrijving: 'Kindvriendelijk & gezellig',
      sfeer: 'Gezin',
      openVoor: 'Lunch',
    ),
  ];

  Future<void> _slaOp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    if (_selectedProfielen.isNotEmpty) {
      final namen = _selectedProfielen.map((i) => _profielen[i].naam).join(',');
      final sfeers = _selectedProfielen.map((i) => _profielen[i].sfeer).join(',');
      final opens = _selectedProfielen.map((i) => _profielen[i].openVoor).join(',');
      await prefs.setString('profiel_naam', namen);
      await prefs.setString('profiel_sfeer', sfeers);
      await prefs.setString('profiel_openVoor', opens);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RestaurantListPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navyDark,
      body: _ImageAchtergrond(
        overlayOpacity: 0.65,
        child: SafeArea(
          child: Column(
            children: [
              // Logo
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                child: Image.asset(
                  'assets/logo_tekst.png',
                  height: 60,
                  errorBuilder: (_, err, stack) => const Text(
                    'Horeca Parels van het Zuiden',
                    style: TextStyle(color: _gold, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Intro tekst
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  'Breda vooruit,\nde klokken luiden!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Profielen
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Wie ben jij?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.2,
                  children: List.generate(_profielen.length, (i) {
                    final p = _profielen[i];
                    final sel = _selectedProfielen.contains(i);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (sel) { _selectedProfielen.remove(i); }
                        else { _selectedProfielen.add(i); }
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: sel ? _gold : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: sel ? _gold : Colors.white,
                            width: sel ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(p.icon, color: sel ? _navyDark : _navy, size: 22),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    p.naam,
                                    style: TextStyle(
                                      color: sel ? _navyDark : _navy,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    p.omschrijving,
                                    style: TextStyle(
                                      color: sel ? _navyDark.withValues(alpha: 0.7) : _navy.withValues(alpha: 0.6),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),

              const Spacer(),

              // Start knop
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _slaOp,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text(
                      'Ontdek de parels',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: _navyDark,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Kaart pagina ─────────────────────────────────────────────────────────────
class _MapPage extends StatefulWidget {
  final List<Restaurant> restaurants;
  final UserState Function(String) stateFor;
  final Future<void> Function() onChanged;

  const _MapPage({
    required this.restaurants,
    required this.stateFor,
    required this.onChanged,
  });

  @override
  State<_MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<_MapPage> {
  static const _bredaCenter = CameraPosition(
    target: LatLng(51.5719, 4.7683),
    zoom: 13.5,
  );

  GoogleMapController? _mapController;
  String? _selectedId;
  Set<Marker> _markers = {};
  LatLng? _userLatLng;

  List<Restaurant> get _metCoords =>
      widget.restaurants.where((r) => r.lat != null && r.lng != null).toList();

  @override
  void initState() {
    super.initState();
    _buildMarkers();
    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      if (mounted) setState(() => _userLatLng = LatLng(pos.latitude, pos.longitude));
    } catch (_) {}
  }

  void _buildMarkers() {
    final markers = <Marker>{};
    for (final r in _metCoords) {
      final isSelected = r.id == _selectedId;
      markers.add(Marker(
        markerId: MarkerId(r.id),
        position: LatLng(r.lat!, r.lng!),
        icon: isSelected
            ? BitmapDescriptor.defaultMarkerWithHue(45.0)    // goud
            : BitmapDescriptor.defaultMarkerWithHue(250.0),  // blauwpaars
        onTap: () {
          setState(() {
            _selectedId = _selectedId == r.id ? null : r.id;
            _buildMarkers();
          });
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(LatLng(r.lat!, r.lng!), 15),
          );
        },
      ));
    }
    _markers = markers;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedId != null
        ? _metCoords.firstWhere((r) => r.id == _selectedId, orElse: () => _metCoords.first)
        : null;

    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Kaart', style: TextStyle(fontWeight: FontWeight.w800)),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '${_metCoords.length} parels',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _bredaCenter,
            markers: _markers,
            myLocationEnabled: _userLatLng != null,
            myLocationButtonEnabled: _userLatLng != null,
            mapType: MapType.normal,
            zoomControlsEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
            },
            onTap: (_) {
              if (_selectedId != null) {
                setState(() {
                  _selectedId = null;
                  _buildMarkers();
                });
              }
            },
          ),

          // Restaurant info kaartje onderin
          if (selected != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RestaurantDetailPage(
                      restaurant: selected,
                      state: widget.stateFor(selected.id),
                      onChanged: widget.onChanged,
                      allRestaurants: widget.restaurants,
                      resolveState: widget.stateFor,
                    ),
                  ));
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _navy.withValues(alpha: 0.12)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: selected.photoName != null
                              ? CachedNetworkImage(
                                  imageUrl: PlacesService.photoUrl(selected.photoName!),
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => const ColoredBox(color: Color(0xFF2D2F6B)),
                                  errorWidget: (context, url, error) => Container(color: _navy),
                                )
                              : Container(
                                  color: _navy,
                                  child: Center(
                                    child: Icon(_cuisineIcon(selected.cuisines),
                                        color: Colors.white.withValues(alpha: 0.6), size: 28),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(selected.name,
                                style: const TextStyle(
                                    color: _navy, fontWeight: FontWeight.w800, fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (selected.wijk.isNotEmpty) selected.wijk,
                                if (selected.prijs != null) selected.prijs!,
                                if (selected.googleRating != null)
                                  '${selected.googleRating!.toStringAsFixed(1)} ★',
                              ].join(' · '),
                              style: TextStyle(
                                  color: _navy.withValues(alpha: 0.55), fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            Text('Tik voor details →',
                                style: TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Centreer op mij knop
          if (_userLatLng != null)
            Positioned(
              bottom: selected != null ? 110 : 16,
              right: 16,
              child: FloatingActionButton.small(
                backgroundColor: Colors.white,
                onPressed: () {
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLngZoom(_userLatLng!, 15),
                  );
                },
                child: const Icon(Icons.my_location_rounded, color: _navy),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Mijn Voorkeuren pagina ────────────────────────────────────────────────────
class _VoorkeureNPage extends StatefulWidget {
  const _VoorkeureNPage();

  @override
  State<_VoorkeureNPage> createState() => _VoorkeureNPageState();
}

class _VoorkeureNPageState extends State<_VoorkeureNPage> {
  Set<int> _selectedProfielen = {};

  static const _profielen = [
    (
      icon: Icons.sports_bar_rounded,
      naam: 'Kroegtijger',
      omschrijving: 'Borrel, bier & kroegsfeer',
      sfeer: 'Bourgondisch',
      openVoor: 'Borrel',
    ),
    (
      icon: Icons.table_restaurant_rounded,
      naam: 'Tafelgenoot',
      omschrijving: 'Lekker tafelen & een goed diner',
      sfeer: 'Romantisch',
      openVoor: 'Diner',
    ),
    (
      icon: Icons.wb_twilight_rounded,
      naam: 'Dagstarter',
      omschrijving: 'Ontbijt, brunch & koffie',
      sfeer: 'Gezellig',
      openVoor: 'Ontbijt',
    ),
    (
      icon: Icons.family_restroom_rounded,
      naam: 'Gezinsbourgondiër',
      omschrijving: 'Kindvriendelijk & gezellig',
      sfeer: 'Gezin',
      openVoor: 'Lunch',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _laadVoorkeuren();
  }

  Future<void> _laadVoorkeuren() async {
    final prefs = await SharedPreferences.getInstance();
    final namen = prefs.getString('profiel_naam') ?? '';
    if (namen.isEmpty) return;
    final namenSet = namen.split(',').toSet();
    setState(() {
      _selectedProfielen = {
        for (var i = 0; i < _profielen.length; i++)
          if (namenSet.contains(_profielen[i].naam)) i,
      };
    });
  }

  Future<void> _slaOp() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedProfielen.isNotEmpty) {
      final namen = _selectedProfielen.map((i) => _profielen[i].naam).join(',');
      final sfeers = _selectedProfielen.map((i) => _profielen[i].sfeer).join(',');
      final opens = _selectedProfielen.map((i) => _profielen[i].openVoor).join(',');
      await prefs.setString('profiel_naam', namen);
      await prefs.setString('profiel_sfeer', sfeers);
      await prefs.setString('profiel_openVoor', opens);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voorkeuren opgeslagen!')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Mijn voorkeuren',
            style: TextStyle(fontWeight: FontWeight.w800)),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _navy.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Wie ben jij?',
                        style: TextStyle(
                          color: _navy,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ...List.generate(_profielen.length, (i) {
                      final p = _profielen[i];
                      final sel = _selectedProfielen.contains(i);
                      return Padding(
                        padding: EdgeInsets.only(bottom: i < _profielen.length - 1 ? 10 : 0),
                        child: GestureDetector(
                          onTap: () => setState(() {
                            if (sel) { _selectedProfielen.remove(i); }
                            else { _selectedProfielen.add(i); }
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              color: sel ? _gold : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: sel ? _gold : _navy.withValues(alpha: 0.18),
                                width: sel ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(p.icon, color: sel ? _navyDark : _navy, size: 24),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p.naam,
                                          style: TextStyle(
                                            color: sel ? _navyDark : _navy,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          )),
                                      Text(p.omschrijving,
                                          style: TextStyle(
                                            color: sel
                                                ? _navyDark.withValues(alpha: 0.7)
                                                : _navy.withValues(alpha: 0.55),
                                            fontSize: 12,
                                          )),
                                    ],
                                  ),
                                ),
                                if (sel)
                                  const Icon(Icons.check_circle_rounded, size: 20, color: _navyDark),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _slaOp,
                    style: FilledButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: _navyDark,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Opslaan',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
